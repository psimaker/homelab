# `kubernetes/apps/` — Tier-1 workloads

This directory holds the GitOps definitions for every Tier-1 (k3s) workload.
The Flux `apps` Kustomization in
[`kubernetes/flux-system/gotk-sync.yaml`](../flux-system/gotk-sync.yaml) points
at this directory, depends on the `infrastructure` layer being healthy, and
reconciles every minute.

See [`docs/architecture.md`](../../docs/architecture.md) for the bigger picture
— in particular the Tier-1 / Tier-2 split and the namespace conventions.

## Layout

```
kubernetes/apps/
├── kustomization.yaml          ← kustomize-config aggregator (lists every app)
├── README.md                   ← this file
└── <app-name>/
    ├── kustomization.yaml      ← kustomize-config, lists every resource in this app
    ├── namespace.yaml
    ├── deployment.yaml         ← or HelmRelease, or both
    ├── service.yaml
    ├── ingressroute.yaml       ← Traefik IngressRoute (not Ingress)
    ├── networkpolicy.yaml      ← default-deny + selective allows, mandatory
    ├── poddisruptionbudget.yaml
    ├── horizontalpodautoscaler.yaml
    ├── servicemonitor.yaml     ← Prometheus scrape config
    ├── prometheusrule-recording.yaml ← recording rules feeding the SLOs
    ├── slos.yaml               ← Sloth PrometheusServiceLevel
    └── secret.sops.yaml        ← SOPS-encrypted Secret manifests
```

The exact set of files depends on the app. The bar for a Tier-1 service is:

| Concern         | Required artefact                                |
| --------------- | ------------------------------------------------ |
| Workload        | `Deployment` (or `StatefulSet` / `HelmRelease`)  |
| Network exposure| `Service` + Traefik `IngressRoute`               |
| Network policy  | `NetworkPolicy` with default-deny ingress+egress |
| Disruption      | `PodDisruptionBudget` if `replicas > 1`          |
| Scaling         | `HorizontalPodAutoscaler` for stateless apps     |
| Observability   | `ServiceMonitor` and a Sloth `PrometheusServiceLevel` for Tier-1 |
| Secrets         | `*.sops.yaml` only — never plaintext             |
| Config          | `ConfigMap` (in-tree) for stable config; secrets via `secret.sops.yaml` |

## Adding a new app — checklist

1. Create `kubernetes/apps/<name>/` with the files above.
2. Pin the container image with a `# renovate:` comment so Renovate tracks it.
3. Encrypt any secrets with SOPS. Use the recipients in [`/.sops.yaml`](../../.sops.yaml).
4. Append `<name>` to the `resources:` list in
   [`kustomization.yaml`](kustomization.yaml).
5. Open a PR. CI runs `kubeconform`, `yamllint`, and `gitleaks`; all three must
   pass before merge.
6. After merge, watch Flux:
   ```sh
   flux get kustomizations apps --watch
   flux logs --kind Kustomization --name apps -f
   ```

## Conventions in this directory

- Every resource carries the labels
  `app.kubernetes.io/name`, `app.kubernetes.io/part-of`, and `tier: tier-1`.
- Container images use `# renovate: datasource=docker depName=<name>`-style
  hints inline above the image string.
- Secret manifests are `*.sops.yaml`. Plaintext `Secret` manifests are
  blocked by `pre-commit` and CI.
- Comments only for non-obvious choices. The reader is assumed to know
  Kubernetes; we explain *why*, not *what*.
