# ADR-0001 — Tier-1 / Tier-2 split

- **Status:** Accepted
- **Date:** 2025-08-14
- **Tags:** platform, strategy, kubernetes

## Context

The home server (`airbase`) has been running roughly fifty Docker Compose
containers for years. Among them are workloads that own real state:
several terabytes of media in Plex, a multi-hundred-gigabyte Immich photo
library, a Nextcloud-AIO instance with active calendars and contacts, a
Vaultwarden vault that family members depend on, and a Gitea instance that
hosts both private code and the primary mirror of this very repository.
That setup works. It has survived Docker upgrades, kernel upgrades, and a
disk migration. People I know are using it daily.

At the same time, I want to host [loogi.ch](https://loogi.ch) — a public
SearXNG-based search engine — and a small set of new admin services on
infrastructure that I can rebuild from zero, version in Git, and update via
pull requests. The temptation is to "just put everything on Kubernetes".
The risk is doing a six-month replatforming project for services that have
nothing to gain from it, and breaking a working setup along the way.

## Decision

I will run two tiers in one repository. **Tier-1** is a Kubernetes (k3s)
cluster across a Hetzner edge node and `airbase` as a worker, managed via
Flux. New services land here, plus anything that benefits from
horizontal scaling, reproducibility, or GitOps-driven dependency updates.
**Tier-2** is the existing Docker Compose dataplane on `airbase`. It stays
in place. Compose files live in `compose/` as 1:1 snapshots of what runs;
Ansible owns the host. Nothing currently in Tier-2 gets moved to Tier-1
unless I have a concrete reason that pays for the migration cost.

## Consequences

### Positive

- The replatforming risk on stateful services drops to zero — they are
  not being replatformed.
- New work gets the Kubernetes hygiene I want (declarative, versioned,
  Renovate-friendly) without paying a migration tax for it.
- Failure domains stay separate: a k3s control-plane bug cannot kill
  Plex.
- The repository stays honest about what is actually running: Tier-2 is
  documented, not hidden.

### Negative

- Two operational models to keep in my head: `kubectl` and `flux` for
  one tier, `docker compose` and `systemctl` for the other.
- Two reverse-proxy / TLS stacks (see ADR-0005), at least until I make a
  different decision later.
- Observability has to cross the tier boundary, which adds setup work
  (see ADR-0008).

### Neutral / known unknowns

- The boundary between tiers is policy, not technology. I will need to
  enforce it through review rather than tooling.

## Alternatives considered

### Option A — Migrate everything to Kubernetes

The "clean" answer. I rejected it because the migration cost for Plex,
Immich, and Nextcloud is high, the operational benefit is low (they are
single-replica stateful services either way), and I would be carrying
the risk of breaking working production on a self-imposed schedule.

### Option B — Stay on Compose, skip Kubernetes entirely

Also tempting, since Compose works. Rejected because new services and
LOOGI specifically benefit from Renovate-driven GitOps, declarative
ingress, and a repeatable cluster-from-zero story — none of which fit
Compose comfortably without reinventing the wheel.

## Notes

Revisit when: a Tier-2 service grows a real need to scale horizontally,
or when Compose tooling diverges enough from upstream that maintenance
cost crosses the migration cost.
