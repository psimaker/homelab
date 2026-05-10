# ADR-0006 — Pocket-ID over Authentik

- **Status:** Accepted
- **Date:** 2026-01-08
- **Tags:** identity, oidc

## Context

New Tier-1 admin services (Grafana, Hubble UI, future Headscale admin,
internal dashboards) want OIDC. There is also Vaultwarden and a small
set of legacy Tier-2 services I might point at OIDC eventually. The
working count is around five OIDC clients today, with maybe ten
realistic over the next two years. The user count is one — me — with
occasional family-member access for Nextcloud and Vaultwarden, neither
of which currently uses external OIDC.

For an organisation with employees, contractors, group-based
authorisation, multiple authentication factors per user, SCIM
provisioning, and an enterprise compliance story, **Authentik** is the
right tool. It is also four containers (server, worker, Postgres,
Redis), and tuning it correctly is its own ongoing project. Running it
"because that is what serious homelabs run" would be cargo-culting; the
features I would actually use are: "WebAuthn login" and "issue an OIDC
token to Grafana".

## Decision

I am using **Pocket-ID** as the OIDC provider for new Tier-1 admin
services, hosted at `id.example.com` in the `identity` namespace. It
runs as a single container with a SQLite database backed by a Longhorn
PVC. Authentication is passkey-only (WebAuthn). OIDC clients are
configured declaratively in the Pocket-ID admin UI, with the resulting
client secrets pulled into other services via SOPS-encrypted Secrets
(see ADR-0004).

## Consequences

### Positive

- One container, one SQLite file, one Longhorn volume. The whole
  identity provider fits in a backup window I do not have to think
  about.
- Passkey-only authentication is a feature, not a constraint — it is
  the auth model I want for a personal admin plane.
- Resource footprint is negligible compared to Authentik's worker +
  Postgres + Redis + server.
- Configuration surface is small enough to read in an afternoon.

### Negative

- Smaller community than Authentik. If I hit a bug, the upstream
  maintainer count is lower. Mitigated by not depending on exotic
  features.
- No SAML support today. Acceptable: nothing in my stack speaks SAML
  that does not also speak OIDC.
- No group-based authorisation logic beyond simple allowlists. If I
  ever need "this group can do X but not Y", I will have to revisit.

### Neutral / known unknowns

- If a future service requires SAML or LDAP, the natural path is to
  put that single service behind Authelia or to bite the bullet on
  Authentik. The OIDC clients will not need to be re-configured.

## Alternatives considered

### Option A — Authentik

The default recommendation in the self-hosted ecosystem in 2026.
Rejected because the operational footprint (four containers, two
stateful dependencies) and configuration complexity are wildly
disproportionate to "five OIDC clients and one human user". Authentik
is a great answer to a question I am not asking.

### Option B — Keycloak

The enterprise standard. Rejected for the same reason as Authentik plus
the JVM operational profile (heap tuning, restart times, image size).
The features I would use are a strict subset of what Pocket-ID
provides.

### Option C — Authelia

A reasonable middle-ground until 2024-ish; in 2026 the impression I have
from following its release cadence and community discussions is that
mindshare is moving elsewhere. I am not willing to bet new infra on a
project I am unsure will be actively developed in two years.

## Notes

Linked from `architecture.md` (Tier-1 workloads table). Revisit when:
a service requires SAML, LDAP, or multi-tenant identity; or when
Pocket-ID upstream stalls.
