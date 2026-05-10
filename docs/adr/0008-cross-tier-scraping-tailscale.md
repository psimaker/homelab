# ADR-0008 — Cross-tier scraping over the Tailscale mesh

- **Status:** Accepted
- **Date:** 2026-01-22
- **Tags:** observability, networking

## Context

Tier-1 runs `kube-prometheus-stack` and Loki on the k3s cluster. Tier-2
runs ~50 Docker Compose services on `airbase`, including `node_exporter`
on the host, several `cadvisor`-style sidecars, the existing Plex /
Immich / Nextcloud workloads, and the host-level NUT and `fail2ban`
exporters. The two tiers were deliberately split (ADR-0001), but
"observability ends at the tier boundary" is not a real option —
half the operational risk lives on `airbase`, and I want one Grafana,
one Alertmanager, one runbook surface.

The constraint is: there is no public scrape surface. `airbase` does
not have public IPv4 ingress (see `architecture.md`), and exposing
`/metrics` on the public internet for scraping would be an attack
surface I do not want, even with bearer tokens. Tier-1 control-plane
already terminates inbound public traffic at the edge; Tier-2 should
not.

## Decision

Prometheus on Tier-1 scrapes Tier-2 exporters **over the Tailscale
mesh**, using the `airbase.tailnet` IP (`100.64.0.2`) as the target
host. ScrapeConfig resources live in
`kubernetes/infrastructure/observability/scrape-configs/`. Promtail on
`airbase` (or rather, the Docker `loki` log driver) pushes to
`http://loki.observability.svc.cluster.local:3100` via the same tailnet
endpoint. The scrape paths and pull/push directions follow whatever the
exporter supports natively; the only invariant is that the traffic
travels the tailnet.

This decision is downstream of ADR-0012 (Headscale + Tailscale): the
mesh exists, ACLs are versioned, the tailnet is reachable from inside
the cluster via the Tailscale Operator subnet router. I am reusing it
rather than building a parallel mechanism.

## Consequences

### Positive

- No public scrape surface. `airbase`'s `/metrics` endpoints stay
  bound to the tailscale interface.
- One mTLS-equivalent boundary (WireGuard) covers all cross-tier
  traffic.
- ACL changes are made in `acl.hujson` and reviewed like any other
  code change.
- No secondary VPN to operate.

### Negative

- Tailnet outage = scrape gap. Mitigated by the fact that a tailnet
  outage is also a "the operator cannot reach airbase" outage, which
  has its own visibility through Beszel push-mode metrics.
- Coupling Prometheus's scrape targets to tailnet IPs means a tailnet
  IP change is a config change. Acceptable: tailnet IPs are stable in
  Headscale unless I explicitly rotate.
- Network-level latency on cross-region scrapes (DE → CH) shows up in
  Prometheus's own `up` metric noise. Acceptable; alerts use
  multi-window evaluation.

### Neutral / known unknowns

- If Tier-2 grows enough exporters that scrape volume becomes
  meaningful, I may switch the busiest ones to remote_write
  (push-based) and keep pull-based for the rest. Right now scrape
  volume is small.

## Alternatives considered

### Option A — Push-based via Prometheus `remote_write`

Run a small Prometheus or Grafana Agent on `airbase`, scrape locally,
remote-write to Mimir or to the Tier-1 Prometheus's `remote_write`
endpoint. Rejected for now because it doubles the moving parts (a
second Prometheus to maintain) for a scrape volume that is small. If
volume grows, this is the natural escalation.

### Option B — A separate VPN (raw WireGuard, OpenVPN, ZeroTier)

Stand up a second mesh just for observability. Rejected because
ADR-0012 already settled the mesh question, and adding a second VPN
solely for scrape traffic is a non-trivial complexity tax for a
benefit ("isolation") I do not currently need.

## Notes

Linked from `architecture.md` (observability section) and ADR-0012.
Revisit when: Tailscale ACL semantics change in a way that makes
scrape-target ACL too coarse-grained; or when scrape volume justifies
a push-based architecture.
