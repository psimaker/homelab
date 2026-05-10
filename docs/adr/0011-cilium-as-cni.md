# ADR-0011 — Cilium as the k3s CNI

- **Status:** Accepted
- **Date:** 2025-12-15
- **Tags:** kubernetes, networking, cilium

## Context

k3s ships with Flannel as the default CNI. It works, it is simple,
and for many homelabs it is the right answer. The cluster here is two
nodes — `edge` in Hetzner Falkenstein and `airbase` in Zurich —
connected over a Tailscale mesh (see ADR-0012). Pod-to-pod traffic
already crosses a WireGuard tunnel, so the CNI's own encryption is
redundant; the question is what other features I want from the
network layer over the next two years.

The list, in priority order: eBPF-based observability for pod-level
flow data (Hubble), a path to **Gateway API** (Traefik's
`HTTPRoute` is on its roadmap, and I want to be ready for that
transition without rebuilding the network layer), and
**NetworkPolicy** enforcement that I trust enough to actually use
beyond default-allow. Flannel does none of these well — it is a
data-plane, not a policy or observability surface.

## Decision

I am replacing Flannel with **Cilium** at install time. The current
pinned version is `1.17.0`. Cilium runs in chaining-friendly mode,
kube-proxy is **kept** (rather than running Cilium in
kube-proxy-replacement mode) to minimise blast radius on the first
deployment. Hubble is enabled and the UI is exposed only on the
Tailscale mesh (consistent with ADR-0009). Gateway API support is
installed but not used yet — Traefik IngressRoute remains the
ingress for now, and the Gateway API path is a Day-2 migration.

## Consequences

### Positive

- Hubble gives pod-level flow visibility without instrumenting any
  application code — useful both for debugging and for catching
  unexpected egress.
- NetworkPolicy enforcement is real (eBPF, no kube-proxy iptables
  pile-up). I can lock down identity-namespace egress without
  hand-rolling iptables.
- Gateway API is first-class. When I do migrate ingress, the network
  layer is already ready.
- The Cilium ecosystem (operator, CLI, Helm chart, Renovate-tracked
  releases) is a known quantity in 2026; Renovate auto-merge of
  patch + minor releases works without surprises.

### Negative

- More moving parts than Flannel: an operator, a daemonset, a Hubble
  relay, a Hubble UI. Each is a thing that can break.
- Initial install requires careful k3s flags (`--flannel-backend=none`,
  `--disable-network-policy`) — getting these wrong leaves the
  cluster networkless. The Ansible playbook captures the right shape;
  manual installs need the runbook.
- Keeping kube-proxy is a deliberate "boring choice" that costs some
  performance on large clusters. Acceptable: this cluster has two
  nodes, the proxy load is rounding error.

### Neutral / known unknowns

- Cilium's release cadence is fast. I will pin a version, let
  Renovate open PRs for patches, and treat minor bumps as a deliberate
  decision rather than auto-merge.

## Alternatives considered

### Option A — Stay with Flannel

The default. Rejected because every interesting next step
(observability, NetworkPolicy, Gateway API readiness) requires
something Flannel does not provide.

### Option B — Calico

Mature, well-understood, NetworkPolicy story is good. Rejected
because the eBPF data-path and Hubble UI are specifically what I
want, and Calico's eBPF mode is supported but not the upstream
default — the centre of gravity in 2026 is Cilium.

### Option C — Antrea

A reasonable choice with a smaller community. Rejected because
ecosystem depth (Helm charts, Ansible roles, runbooks, blog posts at
2 AM) matters more than feature parity for a single-operator cluster.

## Notes

Linked from `architecture.md` (substrate section). Revisit when:
Cilium's release cadence stalls; when Gateway API is mature enough to
replace IngressRoute as the default; or when kube-proxy-replacement
becomes the obvious next step (i.e., when I am confident enough to
take the blast-radius risk).
