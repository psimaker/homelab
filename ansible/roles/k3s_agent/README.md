# `k3s_agent`

Installs k3s in `agent` mode on airbase and joins it to the edge server
over the Tailscale mesh. Co-exists with the running Docker daemon — the
two snapshotters are aligned (`overlayfs`) so they don't fight over images.

## What it does

- Renders `/etc/rancher/k3s/config.yaml` for the agent: server URL,
  Tailscale node IP, snapshotter, kubelet reservations.
- Waits for the server on `100.64.0.1:6443` to be reachable before
  attempting to join.
- Runs `https://get.k3s.io` once with `INSTALL_K3S_VERSION` pinned and
  `K3S_URL` / `K3S_TOKEN` from inventory + SOPS.
- After install, hops to the server (`delegate_to: edge`) and verifies the
  node has registered.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `k3s_version` | inv | Match the server. |
| `k3s_server_url` | inv | `https://100.64.0.1:6443` (Tailscale of edge). |
| `k3s_token` | SOPS | Same token the server was started with. |
| `k3s_agent_node_ip` | `tailscale_ip` | Where kubelet advertises itself. |

## Tags

`k3s`, `k3s_agent`.

## Why airbase is also an agent

GPU access, RAM, and failure-domain diversity (a Hetzner outage shouldn't
take everything down). The home server contributes its compute to Tier-1
without giving up Tier-2 — both stacks run on the same kernel, isolated by
namespaces and cgroups.
