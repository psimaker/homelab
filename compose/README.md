# compose/ — Tier-2 Docker Compose snapshots

This directory contains 1:1 snapshots of the Docker Compose stacks that run on
`airbase`, the bare-metal Debian Tier-2 dataplane host. The full design context
lives in [`docs/architecture.md`](../docs/architecture.md), and the rationale
for keeping these workloads on Compose instead of rehoming them on Kubernetes
is in [ADR 0001](../docs/adr/0001-tier1-tier2-split.md).

## Source of truth

The files here are **snapshots, not the running configuration**. The running
source of truth is `airbase:/data/<stack>/`, materialised on-host by Ansible
from a SOPS-encrypted inventory variable. Mirroring back to this directory is a
manual `scp` step (deliberately — it forces a review when secrets churn).

If you change a compose file in this repo and don't push it to airbase, nothing
happens. If you change it on airbase and don't mirror it back, the public copy
goes stale. The drift is intentionally observable; it is not auto-reconciled.

## Conventions

- **Filename** matches whatever airbase uses today — `compose.yml`,
  `docker-compose.yml`, or `compose.yaml`. We do not normalise. Real-world
  inconsistency is preserved so that `scp` round-trips work without rename.
- **Secrets** are redacted to `${VAR}` placeholders. Each stack ships a
  `.env.example` with every variable it references and a one-line gloss of
  what to put there. The real `.env` files live only on airbase.
- **`.gitignore`** in every stack directory blocks `.env` so a careless `cp`
  cannot leak secrets into the public mirror.
- **`# renovate: datasource=docker`** comments above tracked `image:` lines
  let Renovate open PRs against the snapshots; the host Ansible role copies
  the merged version back onto airbase on the next apply.
- **`com.centurylinklabs.watchtower.enable=true`** marks containers that opt
  into Watchtower's pull cycle (every 3 days at 04:00 Europe/Zurich, see
  [`watchtower/`](watchtower/)). Containers without the label are pinned by
  hand.

## Networking

All public-facing stacks attach to a shared external Docker network called
`proxy-net`. **Nginx Proxy Manager owns this network** — it is the only
container with both a host port published (80/443) and a route into
`proxy-net`. Every other service reaches the world by NPM proxying to its
container hostname on `proxy-net`, which is why most stacks below have no
`ports:` section.

This is the Tier-2 ingress contract:

```
internet --> Cloudflare DNS --> NPM (host ports 80/443) --> service:port on proxy-net
```

The Tier-1 ingress contract (Cloudflare Tunnel --> Traefik) is independent and
documented in [ADR 0005](../docs/adr/0005-tls-zwei-issuer.md).

## Watchtower update flow

Watchtower scans for the `com.centurylinklabs.watchtower.enable=true` label,
pulls fresh tags every 3 days at 04:00, posts a digest to the homelab ntfy
channel, and rolls containers one at a time (`WATCHTOWER_ROLLING_RESTART=false`
intentionally — for a single host, sequential restart is safer than rolling).
A failed pull leaves the running container in place; nothing is deleted until a
new image is verified pullable.

Stacks that should NOT be auto-updated (e.g. major-version-pinned databases)
omit the label. Renovate still opens PRs against their pinned tags so a human
can review and bump.

## Adding a new stack

1. Create `compose/<name>/` with the file pattern documented in
   [`docs/architecture.md`](../docs/architecture.md#adding-a-new-tier-2-stack).
2. Add the stack's secrets to the SOPS-encrypted Ansible inventory.
3. Run `ansible-playbook playbooks/airbase.yml --tags compose-<name>` to
   materialise `/data/<name>/` on the host.
4. `docker compose up -d` from on-host (Ansible does not auto-start; intentional
   gating).
