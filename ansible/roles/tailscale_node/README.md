# `tailscale_node`

Installs the official Tailscale client and enrols it against the
self-hosted Headscale control-plane.

## What it does

- Adds Tailscale's signing key and apt repo.
- Installs the `tailscale` package and ensures `tailscaled` is running.
- Reads `tailscale status --json`. If `BackendState != Running`, calls
  `tailscale up` with:
  - `--login-server={{ headscale_url }}`
  - `--authkey={{ tailscale_authkey }}` (from SOPS)
  - `--advertise-tags={{ tailscale_tags }}`
  - `--hostname={{ inventory_hostname }}`
  - `--accept-routes` (configurable)

The pre-auth key is `no_log: true` so it never lands in the run log.

## The chicken-and-egg

Headscale is a Tier-1 workload — it runs *inside* the k3s cluster that this
role bootstraps. On the very first boot of a new homelab there is therefore
no Headscale to enrol against.

The bootstrap order resolves this in three steps:

1. Skip this role on the first run by passing `--skip-tags tailscale`. Edge
   comes up on its public IPv4; airbase joins via LAN.
2. After k3s is up, deploy Headscale by Flux (it's in
   `kubernetes/infrastructure/identity/headscale/`).
3. Generate a pre-auth key with `headscale preauthkeys create --user homelab`,
   re-encrypt the inventory secrets file, then run
   `ansible-playbook playbooks/site.yml --tags tailscale_node`.

After step 3 every subsequent reconfigure is just `ansible-playbook site.yml`
and this role is idempotent.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `headscale_url` | `https://hs.psimaker.org` | Login server. |
| `tailscale_tags` | `[tag:node]` | Match the Headscale ACL tag list. |
| `tailscale_authkey` | (SOPS) | Pre-auth key, single-use unless `reusable`. |
| `tailscale_accept_routes` | `true` | Accept advertised subnets. |

## Tags

`tailscale`, `tailscale_node`.
