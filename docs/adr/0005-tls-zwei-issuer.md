# ADR-0005 — Two TLS issuers, deliberately

- **Status:** Accepted
- **Date:** 2025-10-12
- **Tags:** tls, ingress

## Context

The two-tier split from ADR-0001 left two reverse-proxy stacks in
place: Traefik v3 in front of Tier-1 services on Kubernetes, and the
existing Nginx Proxy Manager (NPM) on `airbase` in front of Tier-2
services on Docker Compose. NPM has been managing certificates for
about thirty Tier-2 hostnames for years, with HTTP-01 ACME challenges
through its built-in Let's Encrypt integration. It works, the
certificates renew, the operator UI is convenient when adding a new
host on the fly.

For Tier-1 I want wildcard certificates (`*.loogi.ch`,
`*.example.com`'s Tier-1 sub-zone) and DNS-01 challenges, because the
Cloudflare Tunnel ingress means HTTP-01 against the upstream is messy
and because wildcards keep the IngressRoute manifests simple. That is a
clean fit for cert-manager with the Cloudflare DNS-01 solver.

The temptation is to "unify" by moving Tier-2 onto cert-manager too.
That migration costs operator-time without changing what users see.

## Decision

I run **two TLS issuers**. Tier-1 uses **cert-manager** with a
ClusterIssuer doing DNS-01 against Cloudflare for wildcards and
specific hostnames. Tier-2 keeps **NPM's built-in ACME** with HTTP-01
for the existing per-host certificates. Both issuers point at Let's
Encrypt production. The split is documented at the boundary
(`architecture.md` and this ADR); operationally it is invisible to
users.

## Consequences

### Positive

- No migration tax on Tier-2. The thirty existing certificates keep
  renewing the way they always have.
- Tier-1 gets the wildcard / DNS-01 setup it actually needs without
  forcing it onto Tier-2.
- Each tier's TLS story matches its proxy choice — cert-manager fits
  Traefik IngressRoute idiomatically; NPM's built-in ACME fits its UI
  model.

### Negative

- Two places to look when a renewal fails, and two sets of
  alerts/runbooks (`docs/runbooks/cert-renewal-*.md`).
- Different issuance mechanisms (DNS-01 vs HTTP-01) have different
  failure modes — Cloudflare API token issues affect Tier-1 only;
  HTTP-01 reachability issues affect Tier-2 only.

### Neutral / known unknowns

- If NPM upstream goes unmaintained or ships a breaking change, the
  natural migration is "Tier-2 onto cert-manager too", which is then
  cheap because the patterns are already in the repo.

## Alternatives considered

### Option A — Migrate Tier-2 to cert-manager via DNS-01

Technically feasible: install cert-manager standalone or run it on
the k3s agent and inject certificates into NPM via a host-mounted
volume. Rejected because the migration is real work for zero user-visible
benefit, and it would couple Tier-2's certificate availability to the
k3s control plane.

### Option B — A single internal CA (e.g., step-ca, smallstep)

Issue everything from a private CA, install the root on operator
devices, no public ACME. Rejected because public-trusted certificates
are a hard requirement for `loogi.ch` (third-party users) and for any
service a non-operator might want to reach without installing a root.

## Notes

Linked from `architecture.md` (TLS section). Revisit when: NPM upstream
status changes; when a Tier-2 service gains public-facing third-party
users that would prefer a wildcard; or when Cloudflare changes its DNS
API in a breaking way.
