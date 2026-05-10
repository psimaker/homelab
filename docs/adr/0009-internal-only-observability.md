# ADR-0009 — Internal-only observability, no public dashboards

- **Status:** Accepted
- **Date:** 2026-02-04
- **Tags:** observability, security, privacy

## Context

A common pattern in publicly-shared homelab repositories is a public
Grafana, a public status page, sometimes a public Loki at
`logs.example.com`. The recruiter-friendliness is real; the
operational-maturity-signalling is real; the screenshots make great
README headers. The arguments against it are also real: dashboards
leak service inventory, scrape targets, hostnames, sometimes
configuration, and over time accumulate panel queries that were never
designed to be public. A status page leaks uptime patterns. A
public Loki almost always leaks something the operator did not intend.

For this homelab specifically, the tension is sharper. The repository
is public on GitHub as a recruiter-facing artefact (see
`architecture.md`). The temptation to show off observability is
exactly the temptation to widen the attack surface. And the actual
"production" surface — `loogi.ch` — is itself a public service whose
SLO and behaviour are visible to the user every time they hit it.
The dashboard is not the product.

## Decision

There is **no public Grafana, no public Beszel UI, no public status
page, no public Loki, no public Tempo, no public Hubble UI**. Every
observability surface is reachable only via the Tailscale mesh
(`grafana.tailnet`, `beszel.tailnet`, etc.). Authentication on those
surfaces is via Pocket-ID (see ADR-0006), gated by a Tailscale ACL
that limits which devices can reach which observability services. The
public-facing surface is `loogi.ch` itself and the repository.

## Consequences

### Positive

- Attack surface stays narrow. There are no panel queries, scrape
  targets, or dashboard exports leaking through screenshots-by-URL.
- I do not have to harden Grafana for the public internet (which is
  achievable but adds non-trivial maintenance).
- Honest about what observability is: a tool for the operator, not a
  marketing artefact.

### Negative

- The repository looks slightly "less impressive" without a screenshot
  of a Grafana dashboard at a public URL. I am willing to pay that
  price; the trade-off is documented here for anyone reading.
- Onboarding any future co-operator requires getting them onto the
  tailnet first, which adds friction to "can you take a look at this
  alert?".

### Neutral / known unknowns

- If `loogi.ch` traffic grows enough that a public status page becomes
  a real user-facing need (rather than a vanity surface), I will
  revisit. The pattern would then be a separate, narrowly-scoped
  status page that does not share infrastructure with the internal
  stack.

## Alternatives considered

### Option A — Public Grafana with redacted dashboards

Carefully curate which dashboards are public, lock down panel
permissions, put it behind Cloudflare Access. Rejected because the
failure mode is "I forget about a panel and it goes public on the
next Grafana update". The only way to be sure a private dashboard
stays private is to not have a public Grafana at all.

### Option B — A public uptime / status page

Tools like Uptime Kuma, Cachet, or status.io are common. Rejected for
the same reason: the value is mostly aesthetic (recruiter-friendly,
operator-pride), and any meaningful external monitoring of
`loogi.ch` is already happening at the user level — if `loogi.ch` is
down, users notice.

## Notes

Linked from `architecture.md` ("Things deliberately not done").
Revisit when: `loogi.ch` user-base grows enough that a real status
page becomes a user-need; or when a future co-operator scenario
demands easier observability access.
