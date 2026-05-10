# ADR-0012 — Headscale over vanilla WireGuard

- **Status:** Accepted
- **Date:** 2025-10-27
- **Tags:** networking, vpn, identity

## Context

The two-tier topology has nodes in two physical locations (`edge` in
Hetzner Falkenstein, `airbase` at home in Zurich), an operator with at
least three devices (laptop, phone, occasional second laptop), and a
small set of family members who reach Vaultwarden and Nextcloud
remotely. All of these need to share one secure overlay so that
cross-tier traffic, observability scraping (ADR-0008), and remote
operator access can all use the same identity domain. The k8s API
server endpoint and the Hubble UI both live on this overlay; they
must not be reachable from the public internet.

The two serious choices in 2025 are: **Tailscale.com hosted** (with
the Tailscale clients on every node) or **bare WireGuard**, with
something hand-rolled to manage keys, peer config, and routing. The
hosted-Tailscale path is excellent operationally but creates a vendor
dependency for the control plane of the homelab's network, which
sits awkwardly with the "self-host where it pays for itself" policy.
Bare WireGuard is the maximalist self-host answer but is genuinely
painful to operate at small scale (manual peer config, no MagicDNS,
no key rotation tooling, no ACLs as code).

## Decision

I am running **Headscale**, self-hosted on the Tier-1 cluster at
`hs.psimaker.org`, with the standard **Tailscale clients** on every
node and operator device. Headscale is the control plane (key
exchange, ACL distribution, MagicDNS); the data plane is the same
WireGuard implementation Tailscale itself ships. ACLs live as code in
`kubernetes/infrastructure/identity/headscale/acl.hujson` and are
versioned and reviewed like everything else.

Tailnet IP allocation is documented in `architecture.md`; addresses
are stable unless I explicitly rotate.

## Consequences

### Positive

- One identity domain across nodes, operator devices, and (via the
  Tailscale Operator) eventually individual workloads.
- ACLs as code, reviewed in PRs, encrypted-in-rest where they
  reference secrets. No "I changed something in the admin UI three
  months ago" mystery.
- MagicDNS, key rotation, and re-keying are automatic Tailscale-client
  features; I do not have to build any of that.
- No vendor dependency for the control plane. If Headscale upstream
  goes silent, I can run the existing version indefinitely; if I want
  to migrate to hosted Tailscale later, the client side does not
  change.

### Negative

- I am responsible for keeping Headscale up. If it goes down, new
  devices cannot join the tailnet — existing tunnels keep working,
  but key rotation stops. Mitigated by: Headscale is small, the state
  is a SQLite file, and a restic restore + restart is the recovery
  procedure.
- Headscale lags hosted Tailscale on features (no SSH session
  recording, no app connectors, no service discovery beyond MagicDNS).
  None of these are blocking today.
- The Tailscale clients are closed-source on some platforms (iOS).
  Acceptable: the clients are a known quantity and the ecosystem is
  large enough that issues get found.

### Neutral / known unknowns

- If Headscale upstream development pace stalls below "maintained", the
  fallback is hosted Tailscale at $5/month/operator, which is fine —
  the migration is well-understood.

## Alternatives considered

### Option A — Hosted Tailscale.com

Operationally excellent, free for personal use up to 100 devices,
zero infrastructure overhead. Rejected because it puts the network
control plane into a vendor's hands, which is exactly the dependency
the rest of this homelab is structured to avoid. The technical product
is great; the principle is what tips the decision.

### Option B — Bare WireGuard with `wg-quick`

Maximum self-host. Rejected because manually managing N peers, N
public keys, N config files, and a hand-rolled approach to ACLs and
DNS is real work that I would re-do every time a device is added or
rotated. The features I would have to build are, in practice, what
Tailscale-the-client provides.

### Option C — Nebula

Slack's open-source mesh, conceptually similar. Rejected because the
community in 2025 feels deplatformed — releases are rare, the
ecosystem is small, and I am not willing to bet new infra on it.

## Notes

Linked from `architecture.md` (network section), ADR-0008
(observability scraping), and ADR-0009 (internal-only observability).
Revisit when: Headscale upstream stalls; when hosted Tailscale's
pricing or feature set materially changes; or when WireGuard
itself ships in-kernel ACL primitives.
