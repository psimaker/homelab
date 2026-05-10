# terraform/

OpenTofu (1.10.0) configurations that provision the homelab cloud surface:
Hetzner Cloud edge node, Hetzner Object Storage buckets (state + Loki),
Cloudflare DNS / Tunnel / Zero-Trust, and Backblaze B2 buckets for restic.

> See [`docs/architecture.md`](../docs/architecture.md) for the system-level
> picture and [`docs/adr/`](../docs/adr/) for the rationale behind individual
> choices.

## Layout

```
terraform/
├── modules/
│   ├── hetzner-edge-node/   server + firewall + private-network attachment
│   ├── cloudflare-app/      DNS record + tunnel route (+ optional Access policy)
│   └── b2-restic-bucket/    bucket + lifecycle + scoped application key
└── live/
    └── prod/                the only environment (this is a homelab)
```

Modules are deliberately small and parameterised. The `live/prod` root
composes them.

## Prerequisites

- OpenTofu 1.10.0 (`tofu version`) — pin via [`tenv`](https://github.com/tofuutils/tenv)
  using the `.terraform-version` file at this directory's root.
- An age private key at `~/.config/sops/age/keys.txt` matching one recipient
  in [`.sops.yaml`](../.sops.yaml).
- The Hetzner Object Storage bucket `psimaker-tofu-state` must already exist
  before the very first `tofu init`. Create it once by hand in the Hetzner
  Console; from then on, OpenTofu manages it as a resource and recovers
  state from the same bucket.
- Environment variables for the S3 backend credentials:
  ```
  export AWS_ACCESS_KEY_ID=...      # Hetzner Object Storage S3 credential
  export AWS_SECRET_ACCESS_KEY=...
  ```

## Day-1 bootstrap

```bash
# 1. decrypt secrets into a working tfvars file
sops -d live/prod/terraform.tfvars.sops.json > live/prod/terraform.tfvars

# 2. init + plan + apply
cd live/prod
tofu init
tofu plan  -var-file=terraform.tfvars -out=plan.out
tofu apply plan.out

# 3. shred the plaintext copy
shred -u terraform.tfvars
```

Locking is handled natively by the `s3` backend (`use_lockfile = true`,
OpenTofu 1.10+), no DynamoDB.

## Day-2 changes

PR-driven via Gitea Actions:

| Workflow         | When                          |
| ---------------- | ----------------------------- |
| `tofu-plan.yml`  | PR touches `terraform/`       |
| `tofu-apply.yml` | merge to `main`, gated on destructive plans |

Local hands-on changes follow the same `init / plan / apply` flow.

## Modules

| Module                                   | Purpose                                         |
| ---------------------------------------- | ----------------------------------------------- |
| [`modules/hetzner-edge-node`](modules/hetzner-edge-node)   | One Cloud server + firewall + network attachment |
| [`modules/cloudflare-app`](modules/cloudflare-app)         | DNS record + Tunnel route + optional Access app |
| [`modules/b2-restic-bucket`](modules/b2-restic-bucket)     | Backblaze B2 bucket + lifecycle + scoped key    |

## Conventions

- Variables are `snake_case`; resource names are `kebab-case`.
- Sensitive values are marked `sensitive = true` and only ever sourced from
  the SOPS-encrypted `terraform.tfvars.sops.json`.
- Provider versions are pinned in each `versions.tf`. Renovate opens PRs.
- `tofu fmt` and `tofu validate` are enforced by `lint.yml` in CI.

## Outputs that downstream consumes

The `live/prod` root exposes only what Ansible and Flux need:

- `edge_ipv4` — the public IPv4 of the edge node, fed into Ansible inventory
- `tunnel_id` — the Cloudflare Tunnel ID, used by the `cloudflared` Helm chart
- `state_bucket` and `loki_bucket` — referenced by Flux HelmReleases for Loki
