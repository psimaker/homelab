# `k3s_server`

Installs k3s in `server` mode on the edge node. The cluster has exactly one
control-plane host; high availability is delegated to faster recovery, not to
multi-master.

## What it does

- Renders `/etc/rancher/k3s/config.yaml` with cluster CIDRs, the disabled
  components (`traefik`, `servicelb`, `metrics-server`, `local-storage`),
  Cilium-friendly flags (`flannel-backend: none`, `disable-network-policy:
  true`), and TLS SANs for `edge.tailnet`, `hs.example.com`, the Tailscale
  IP.
- Downloads `https://get.k3s.io` once, runs it with `INSTALL_K3S_VERSION`
  pinned, `K3S_TOKEN` from SOPS, no extra flags (everything is in
  config.yaml — easier to diff).
- Waits for `/etc/rancher/k3s/k3s.yaml` to appear and the node to register.
- Fetches the kubeconfig back to `ansible/.local/kubeconfig`, rewriting the
  embedded API URL from `127.0.0.1` to the Tailscale IP so it works from the
  operator's laptop.
- Installs `kubectl` (symlink to the k3s binary), `helm`, and the `flux` CLI.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `k3s_version` | inv | `v1.31.4+k3s1` in inventory. |
| `k3s_token` | SOPS | Cluster join secret, never logged. |
| `k3s_cluster_cidr` / `_service_cidr` / `_cluster_dns` | inv | Default 10.42/16, 10.43/16, 10.43.0.10. |
| `k3s_server_disable_components` | list | Built-ins to disable. |
| `k3s_install_helm` / `_flux` | `true` | Operator CLIs co-located on edge. |

## Tags

`k3s`, `k3s_server`.

## Why server-only on edge

Edge has a public IP, no NAT, stable reachability — the textbook spot for
the API server. Putting it on airbase would mean kubectl-from-anywhere
needs port-forwarding through the home router, defeating the point. See
[`docs/architecture.md`](../../../docs/architecture.md#substrate-and-orchestration).
