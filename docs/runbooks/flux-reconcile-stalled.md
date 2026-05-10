# Runbook — Flux reconcile stalled

> **Triggers:** `flux check` reports a `Kustomization` or `HelmRelease`
> stuck in `Progressing` for >10 m, or the `FluxKustomizationNotReady`
> Prometheus alert (which fires when `flux_reconcile_condition{type="Ready",status="False"}`
> is true for >10 m).
> **Severity:** warning at 10 m, critical at 30 m.
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. `flux check` from operator laptop — overall health.
2. `flux get kustomizations -A` and `flux get helmreleases -A` — find the red rows.
3. `flux logs --kind=Kustomization --namespace=flux-system --tail=100` — what's the actual error?
4. Match the error to one of the **Common causes** below.

## Context

Flux runs four controllers in `flux-system`:
`source-controller`, `kustomize-controller`, `helm-controller`,
`notification-controller`. They reconcile in a loop on the intervals
defined in [`docs/architecture.md`](../architecture.md#flux-topology) — 10 m
for `infrastructure`, 1 m for `apps`, 5 m for HelmReleases.

A stalled reconcile means commits to `main` aren't taking effect in the
cluster. That's not an immediate outage — running workloads keep running —
but it means the cluster is drifting from Git, and any urgent change
(silencing an alert at the source, applying a patched HelmRelease) won't
land.

Flux fails open: a stalled reconcile never *removes* a working workload, it
just refuses to apply the new version.

## Investigate

### Top-level health

```
flux check
# 'all checks passed' is the happy path

flux get kustomizations -A
# look at READY column. Any 'False' is a problem.
flux get helmreleases -A
flux get sources git -A
flux get sources helm -A
```

### Drill into a stuck Kustomization

```
flux get kustomizations -A | grep -v True
NAMESPACE="flux-system"
NAME="apps"
flux logs --kind=Kustomization --name="$NAME" --namespace="$NAMESPACE" --tail=200
kubectl describe kustomization -n "$NAMESPACE" "$NAME" | sed -n '/Events/,$p'
```

### Drill into a stuck HelmRelease

```
flux logs --kind=HelmRelease --name=loogi --namespace=loogi --tail=200
kubectl describe helmrelease -n loogi loogi
```

`Status.Conditions` and `Status.History` are the most useful fields. The
last `Failed` history entry has the upstream Helm error message.

### Source freshness

```
flux get sources git
# READY=True, but is the COMMIT hash recent?
```

If `COMMIT` lags behind `git log -1 main` by minutes, the GitRepository can't
reach Gitea — see DNS/Gitea cause below.

### SOPS decrypt

The single most common stall is SOPS failing to decrypt a Secret manifest:

```
flux logs --kind=Kustomization -A --tail=200 | grep -i 'sops\|decrypt\|age'
```

Typical line: `failed to decrypt: no key could decrypt the data`.

Check the `Secret/sops-age` exists and has the expected key:

```
kubectl -n flux-system get secret sops-age -o yaml | yq '.data | keys'
# expect: ["age.agekey"]
```

### Helm template error

```
helm template loogi ./local-checkout-of-the-chart \
  --values kubernetes/apps/loogi/values.yaml
```

Reproducing the templating step locally is the fastest way to find a
typo. helm-controller's error messages are accurate but terse.

## Common causes

- **SOPS decrypt failed.** Either the `Secret/sops-age` got rotated/deleted
  out from under Flux, or someone (me) committed a SOPS file encrypted to
  only the operator key, not the cluster key. Fix: re-encrypt with both
  recipients (`sops updatekeys`) or restore the cluster's age key Secret.
- **Helm values templating error.** A new field, a misnamed reference, an
  inadvertent indentation change. Usually a Renovate PR that bumped a
  chart and the new chart renamed a value. Catch with `kubeconform` and
  `helm template` in CI; sometimes slips through.
- **GitRepository can't reach Gitea.** Either Gitea on airbase is down,
  Cilium DNS resolution to `git.psimaker.org` is failing, or the
  cross-tier path (edge cluster ↔ airbase Gitea) is broken. See
  [`tailscale-mesh-mtu.md`](tailscale-mesh-mtu.md) and
  [`k3s-node-notready.md`](k3s-node-notready.md).
- **Helm release stuck mid-upgrade with `pending-upgrade` status.** A
  previous reconcile crashed mid-flight and Helm's release record is
  half-baked. Symptom: every retry fails with
  `another operation (install/upgrade/rollback) is in progress`.
- **CRD missing for an applied resource.** Renovate updated a chart whose
  CRDs are managed separately, and the CRD lag broke the next reconcile.

## Mitigation

### Force a reconcile

```
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization apps --with-source
flux reconcile helmrelease loogi -n loogi --with-source
```

### Suspend then resume

When a reconcile is in a bad loop, suspend, fix manually, then resume:

```
flux suspend kustomization apps
# ... do the manual thing ...
flux resume kustomization apps
```

A common pattern is to `flux suspend` a HelmRelease, run
`helm rollback <release> <previous-revision>` directly, then resume.

### Recover a stuck Helm release

```
helm history -n loogi loogi
helm rollback -n loogi loogi <last-known-good-revision>
flux resume helmrelease loogi -n loogi
```

If `helm history` shows `pending-upgrade` and there's no revision to roll
back to, the surgical fix is:

```
kubectl -n loogi delete secret -l owner=helm,status=pending-upgrade
flux reconcile helmrelease loogi -n loogi --with-source
```

That deletes Helm's stuck state record without touching the actual workload
resources.

### "Just stop the page"

```
amtool silence add --alertmanager.url=http://alertmanager.observability.svc:9093 \
  alertname=FluxKustomizationNotReady --duration=1h \
  --comment="In progress, see runbook"
```

### Real fix

Almost every stall I've actually had has been a mistake in a commit (mine or
Renovate's). The "real fix" is the corrective commit. If the commit is
mine, push it. If it's Renovate's, close the PR and pin the chart at the
last-good version in `renovate.json5` until upstream is sorted.

## Postmortem requirement

A reconcile stall by itself is not a postmortem if no workload was affected.
It is one if:

- A workload was offline because Flux couldn't apply a fix.
- The stall lasted >30 m on `infrastructure`.
- A SOPS key issue was involved (rare; high blast radius).

## Related

- Architecture: [GitOps, CI, dependency management](../architecture.md#gitops-ci-dependency-management),
  [Secrets](../architecture.md#secrets)
- ADRs: [`0002-flux-vs-argocd.md`](../adr/0002-flux-vs-argocd.md),
  [`0004-secrets-sops-vs-vault.md`](../adr/0004-secrets-sops-vs-vault.md)
- Sibling runbook: [`cert-renewal-stuck.md`](cert-renewal-stuck.md) (a
  cert-manager renewal that isn't picked up by Flux looks similar at first)
