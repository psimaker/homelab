# `cloudflared_host`

Installs the Cloudflare Tunnel daemon as a host systemd service on edge.
This is a **fallback** ingress path — the primary tunnel runs as an
in-cluster Helm release (see
[`kubernetes/infrastructure/cloudflared/`](../../../kubernetes/infrastructure/cloudflared/)).
The host-level daemon attaches to the same Tunnel UUID; Cloudflare
load-balances between connectors, so when the in-cluster pod is unhealthy
or the cluster itself is being upgraded, traffic still reaches the public
ingress through this side door.

## What it does

- Adds Cloudflare's apt repo key + repo.
- Installs the `cloudflared` package.
- Creates a `cloudflared` system user with no shell.
- Drops the tunnel token (from SOPS, `cloudflared_tunnel_token`) into
  `/etc/cloudflared/tunnel.env` (mode 0600, no_log on the task).
- Renders a hardened systemd unit
  (`/etc/systemd/system/cloudflared.service`) and starts it.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `cloudflared_host_install` | `false` | Gate — only `true` on edge. |
| `cloudflared_tunnel_token` | (SOPS) | Token from Cloudflare Zero-Trust. |

## Tags

`cloudflared`, `cloudflared_host`.

## Why a fallback at all

The in-cluster tunnel pod has hard dependencies on Cilium being healthy and
the API server being reachable. The host daemon has only the kernel and
network-online.target as dependencies, so a control-plane outage doesn't
black out `loogi.ch`. See
[`docs/adr/0011-cloudflared-pod-and-host-fallback.md`](../../../docs/adr/0011-cloudflared-pod-and-host-fallback.md)
when that ADR lands.
