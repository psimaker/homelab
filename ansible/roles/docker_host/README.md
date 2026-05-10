# `docker_host`

Configures airbase as a Docker host for the Tier-2 dataplane. Pulls Docker
CE from `download.docker.com` (NOT the Debian-default `docker.io`, which lags
multiple minor versions and ships a stale buildx).

## What it does

- Adds the upstream Docker apt signing key and repository.
- Removes any `docker.io`, `containerd`, `runc`, `podman-docker`, or
  `docker-compose` shipped by Debian.
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`.
- Renders `/etc/docker/daemon.json` from `docker_daemon_config`. Defaults:
  - `log-driver: json-file` with `max-size=10m`, `max-file=3`
  - `live-restore: true` (containers survive `dockerd` restart)
  - `userland-proxy: false` (less hairpin NAT, fewer surprises)
  - `default-address-pools` set so home/k8s subnets do not collide with
    Docker's default 172.17.0.0/16.
- Appends the operator user to `docker` group.
- Ensures the `proxy-net` external network exists, so existing compose stacks
  (Nginx Proxy Manager + service stacks) attach correctly.
- Installs the Grafana Loki Docker log-driver plugin and aliases it to
  `loki`, so a stack can opt-in via:
  ```yaml
  logging:
    driver: loki
    options:
      loki-url: "http://loki.observability.svc.cluster.local:3100/loki/api/v1/push"
  ```

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `docker_packages` | full set | Add `docker-scan-plugin` etc. via override. |
| `docker_daemon_config` | dict | Merge-friendly. |
| `docker_users` | `[operator_user]` | Add CI runner accounts here. |
| `docker_external_networks` | `[proxy-net]` | Compose-attached external nets. |
| `docker_install_loki_plugin` | `true` | Disable on edge or constrained nodes. |

## Tags

`docker`, `docker_host` — apply this role.

## Why install from upstream

Debian's `docker.io` is at v20-something while upstream is at v27+; buildkit,
compose-v2, and live-restore behaviours diverge meaningfully. We pin to
upstream and let Renovate's apt tracker open PRs.
