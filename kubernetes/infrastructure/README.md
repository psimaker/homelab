# `kubernetes/infrastructure/` — Tier-1 controllers and platform services

Everything in this tree is "the platform": the things `kubernetes/apps/` rely
on to run. A workload in `apps/` should never have to spin up its own ingress
controller or its own Prometheus.

## Subdirectories

| Path             | What lives there                                             | Why                                              |
| ---------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| `controllers/`   | CNI, ingress, certs, secret operators, tunnels, scheduling   | Plumbing that has no useful identity of its own  |
| `storage/`       | Longhorn distributed block storage                           | Stateful workloads' backing store                |
| `observability/` | Prometheus stack, Loki, Promtail, Tempo, Beszel, version alerts | Day-2 operability                              |
| `identity/`      | Pocket-ID, Tinyauth, Headscale                               | Single sign-on + tailnet control-plane           |

## Reconciliation order

The `infrastructure` Flux Kustomization has `wait: true`, so a healthy
reconcile means every workload below `kubernetes/apps/` can rely on:

- A working CNI (`Cilium DaemonSet ready` health-check)
- cert-manager (`cert-manager Deployment ready` health-check)
- Traefik (`traefik Deployment ready` health-check)

If any of these fail, the dependent `apps` Kustomization stays paused. This is
deliberate: a half-bootstrapped cluster should refuse to admit workloads
rather than half-deploy them and then alert on cert errors.

## Per-controller pattern

Every subdirectory follows the same shape:

```
<name>/
├── kustomization.yaml      Lists every file below
├── namespace.yaml          (where applicable)
├── helm-repository.yaml    HelmRepository CRD
├── helm-release.yaml       HelmRelease CRD, references the local ConfigMap below
├── values.yaml             Helm chart values, picked up by ConfigMapGenerator
└── *.sops.yaml             Encrypted Secret manifests (tunnel tokens, API keys, …)
```

The `kustomization.yaml` of each controller uses `configMapGenerator` to build
a `<name>-helm-values` ConfigMap from `values.yaml`, then `valuesFrom:
- kind: ConfigMap, name: <name>-helm-values` in the HelmRelease pulls them in.

This means:
- `values.yaml` files stay scannable by Renovate's `helm-values` matcher
- Diffs in PRs are clean (no inline 200-line YAML blobs in `helm-release.yaml`)
- A single source of truth — no risk of `values:` and the ConfigMap drifting

## Pinning policy

See `docs/architecture.md § Versioning and pinning policy`. Quick rules:

- Chart version pinned in `helm-release.yaml`, with a `# renovate:` comment
  above the `version:` field.
- Container image versions pinned in `values.yaml` (under `image.tag` etc.)
  with a matching Renovate comment.
- The Renovate Helm-release manager picks up the HelmRelease versions
  automatically; the regex manager handles the comment-pinned tags.

## SOPS placeholders

Every `*.sops.yaml` in this tree is committed as a placeholder with the proper
SOPS metadata block but cipher values that match the structure produced by
real encryption. Replace by:

```bash
# Edit the secret in plaintext, then re-encrypt:
sops kubernetes/infrastructure/<dir>/<name>.sops.yaml
```

`sops` reads `.sops.yaml` at the repo root and applies the `age` recipients
defined in the `creation_rules`.
