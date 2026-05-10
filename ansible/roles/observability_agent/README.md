# `observability_agent`

Installs the two host-level observability daemons that don't naturally fit
in the cluster: Promtail (log shipping) and the Beszel agent (uptime
side-channel).

Both daemons reach the in-cluster control-plane (Loki and Beszel hub) over
the Tailscale mesh, so neither requires a public endpoint.

## What it does

### Promtail

- Creates a `promtail` system user with read access to `/var/log` and
  optionally the Docker socket.
- Pins the version (`promtail_version`), downloads the GitHub release zip,
  installs to `/usr/local/bin/promtail`.
- Renders `/etc/promtail/promtail.yaml`:
  - Loki push URL = `http://loki.observability.svc.cluster.local:3100/loki/api/v1/push`
  - Static scrapes for `/var/log/syslog`, `/var/log/auth.log`, plus any
    extra path in `promtail_scrape_paths`.
  - On airbase, Docker SD config to discover containers and label by
    `compose_project` / `compose_service` for natural Grafana filtering.
- Systemd unit binds the metrics endpoint to `tailscale_ip:9080` only.

### Beszel agent

- Creates a `beszel` user.
- Installs the agent binary, points it at `beszel.tailnet:8090`.
- The hub public key (paired interactively in the Beszel UI on first
  enrolment) lives in `beszel_agent_hub_public_key`. Until set, the unit is
  installed but stopped — idempotent for repeated runs.

## Tags

`observability`, `observability_agent`.

## Why on the host instead of as a DaemonSet

Promtail-as-DaemonSet would only cover Tier-1 pods. Tier-2 Docker stacks
(Plex, Nextcloud, Immich, …) live outside k3s; their logs are most natural
to scrape via the host's Docker socket. Running Promtail on the host gives
us one tool covering both tiers with one config.
