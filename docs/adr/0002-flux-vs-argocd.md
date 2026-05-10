# ADR-0002 — Flux over ArgoCD

- **Status:** Accepted
- **Date:** 2025-09-03
- **Tags:** gitops, kubernetes

## Context

With the Tier-1 / Tier-2 split decided in ADR-0001, the new Kubernetes
cluster needs a GitOps controller. The two serious candidates in
mid-2025 are Flux v2 and ArgoCD. Both reconcile a Git repository onto a
cluster, both are mature, both have healthy communities. The decision is
not "which can do the job" — both can — but "which fits a single-operator
homelab where the operator is also the only reviewer".

The forces here are honest ones. I want strict GitOps discipline: if
something is not in Git, it does not exist on the cluster. I want
Renovate to be the thing that opens pull requests for every chart and
image bump. And I know myself well enough to admit that an attractive
web UI with a "sync" button will, eventually, get clicked when I am
tired and the test environment is the production cluster.

## Decision

I am using **Flux v2** as the sole GitOps controller, bootstrapped
against this repository at path `kubernetes/`. There will be no ArgoCD,
no Rancher Fleet, and no "experimental" second controller. The Flux
HelmRelease and Kustomization resources are the only allowed entry
points for cluster state; manual `kubectl apply` is reserved for break-glass
moments and is logged in `docs/runbooks/` when used.

## Consequences

### Positive

- The CLI-first surface keeps me honest. There is no dashboard tempting
  me into one-off changes.
- Flux's `HelmRelease` and `Kustomization` model maps cleanly to how
  Renovate annotates files for image and chart bumps.
- SOPS decryption is a first-class feature in Flux's `Kustomization`
  controller — no sidecar, no extra operator.
- The mental model is small: sources, kustomizations, helm releases,
  notifications. Four controllers, four CRDs to know.

### Negative

- No graphical visualisation of dependency graphs. When something is
  stuck, I read controller logs.
- Onboarding cost for any future co-operator is higher than ArgoCD —
  there is no "look at this UI" path.
- Flux's PR-driven workflow means I cannot "force a sync now" as easily
  as ArgoCD's button; I have to commit or annotate.

### Neutral / known unknowns

- Multi-tenancy features in Flux are improving; I do not need them now,
  but if I ever onboard another operator I will revisit.

## Alternatives considered

### Option A — ArgoCD

The dashboard is genuinely useful, the Application CRD is conceptually
clean, and the ApplicationSet feature is powerful. Rejected because the
UI itself is the problem, not the feature: I do not want a "sync" button
in a homelab where I am the only reviewer and the only operator. The
discipline I lose by having one is not worth the visualisation I gain.

### Option B — Plain `kubectl apply` from CI

The minimalist option: no controller, just a Gitea Actions workflow
that applies manifests on merge to main. Rejected because there is no
drift detection (a manual `kubectl edit` survives until the next push)
and HelmRelease semantics would have to be reimplemented in shell.

## Notes

Revisit when: a second operator is onboarded; or when Flux's release
cadence drops below "maintained". Linked from `docs/architecture.md`.
