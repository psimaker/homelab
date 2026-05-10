# Runbook — Tailscale mesh MTU oddness

> **Triggers:** intermittent connectivity between cluster pods on edge and
> services on airbase; some HTTP requests succeed and some hang; Prometheus
> shows `node_network_transmit_drop_total{device="tailscale0"}` rising on
> one of the nodes; users report "Immich is slow today" while Plex from the
> same network is fine.
> **Severity:** warning (the "your gut says something is wrong" kind)
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. From edge: `ping -M do -s 1450 100.64.0.2` (airbase). Does it succeed?
2. Drop the size: `ping -M do -s 1280 100.64.0.2`. If 1280 works and 1450 doesn't, you're in path-MTU-blackhole territory.
3. `tailscale netcheck` on both nodes — note the reported MTU and the relay status.
4. Restart `tailscaled` on the affected node — does the symptom clear?

If yes to (4) and the symptom returns within 24 h, **this is the runbook**
and the MTU work below is the right answer.

## Context

The chronic homelab problem: **path MTU between airbase and edge**.

Tailscale's WireGuard transport has an effective payload of 1280 bytes by
default after subtracting the WireGuard headers from the host's interface
MTU. In a clean path that's plenty. In our path it isn't always:

- airbase ↔ home router: 1500
- home router ↔ ISP (Swisscom): 1492 (PPPoE)
- ISP ↔ Cloudflare/Hetzner: 1500
- Hetzner internal: 1500

The 1492 PPPoE link is the bottleneck. ICMP "fragmentation needed"
messages from Swisscom's edge are blocked somewhere — almost certainly the
ISP's router (a known issue with consumer fibre boxes), so path MTU
discovery fails silently. TCP just stalls when a large packet vanishes.

The symptom is *intermittent*: small responses (TLS handshake, healthchecks)
work, large responses (image bytes, big API responses) hang on one of the
segments and trigger TCP retransmits. Looks like "the internet is slow" until
you ping with `-M do` and big packet sizes start failing.

## Investigate

### Confirm with the do-not-fragment ping

From edge:

```
ping -M do -s 1500 100.64.0.2
# fragmentation needed and DF set / ttl ... → MTU is too big
ping -M do -s 1450 100.64.0.2
# usually fails
ping -M do -s 1380 100.64.0.2
# usually works
```

Whatever's the largest size that succeeds is your effective path MTU minus
28 (the IP+ICMP overhead). Subtract another 80 for WireGuard and you have
your tailscale0 MTU ceiling.

### Check current Tailscale MTU

```
ip link show tailscale0 | grep -oE 'mtu [0-9]+'
# default: mtu 1280
```

```
tailscale netcheck
# Look at:
#   * UDP: true
#   * IPv4: yes, ...
#   * MappingVariesByDestIP: false
#   * PMTUD: ...
#   * Nearest DERP: ...
```

`PMTUD: false` is a red flag here — it means the kernel's path-MTU discovery
isn't getting through.

### Drop counters

```
ssh root@edge.tailnet 'ip -s link show tailscale0'
ssh root@airbase.tailnet 'ip -s link show tailscale0'
# look at TX errors / drops; non-zero is fine, fast-rising is not
```

### Cilium side

Cilium has its own MTU-aware tunnel (we run it in chaining-friendly mode,
not full encapsulation, but pod-to-pod cross-node still goes via tailscale0
because that's the only L3 path between nodes).

```
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -i mtu
kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint list | head
```

Cilium's `routing-mode` is `tunnel` with VXLAN; that adds another ~50 bytes
of encapsulation. Stack everything together and you can see why naive
defaults don't work at all.

### Hubble flow inspection

```
kubectl -n kube-system exec ds/cilium -- hubble observe --follow \
  --pod loogi/loogi --type drop --since 5m
```

Drops with `reason: 64` (frag-needed) are the smoking gun.

## Common causes

- **ISP path-MTU mismatch (Swisscom PPPoE).** The default. This runbook
  exists because of this. Fixed by lowering tailscale0 MTU.
- **ICMP-blackholed somewhere.** Same effect as above but harder to
  attribute. The fix is the same.
- **Recent Cilium upgrade changed encapsulation.** Renovate-merged a chart
  bump that toggled `routing-mode: tunnel` ↔ `native`. Restoring the explicit
  value in `kubernetes/infrastructure/cni/cilium/values.yaml` fixes it.
- **Tailscale moved us to a DERP relay.** When the direct UDP path
  fails, Tailscale routes via DERP, which has a different effective MTU.
  Less common since direct path normally works.

## Mitigation

### Lower the Tailscale interface MTU

Tailscale picks 1280 by default; we want 1180 to give us margin for the
PPPoE 1492 minus WireGuard overhead minus VXLAN minus a fudge factor.

The clean way is via the systemd unit (Ansible-managed):

`ansible/roles/tailscale/templates/tailscaled.override.conf.j2`:

```ini
[Service]
Environment="TS_DEBUG_MTU=1180"
```

Apply via Ansible, then `systemctl restart tailscaled` on both nodes.

Verify:

```
ip link show tailscale0
# expect mtu 1180

ping -M do -s 1150 100.64.0.2   # should still pass with margin
```

### Alternative: let Cilium handle netfilter

Tailscale's `--netfilter-mode=off` makes it stop programming iptables rules
and lets Cilium's eBPF rules win. This used to be necessary; with Cilium
1.17 + chaining mode it's cleaner not to need it. Mentioned for completeness.

### "Just stop the symptoms"

Restarting `tailscaled` clears the existing WireGuard sessions and
re-negotiates. Often the new sessions pick a slightly different relay
and the symptom disappears for hours-to-days. A useful diagnostic but not
a fix.

## Postmortem requirement

This one rarely meets the postmortem bar (it's slow, intermittent, not a
hard outage). It does meet it if it caused user-visible failures on
`loogi.ch` for >5 min cumulatively in a 24 h window.

## Related

- Architecture: [Network and identity](../architecture.md#network-and-identity)
- ADRs: [`0011-cilium-as-cni.md`](../adr/0011-cilium-as-cni.md),
  [`0012-headscale-vs-vanilla-wireguard.md`](../adr/0012-headscale-vs-vanilla-wireguard.md)
- Sibling runbook: [`k3s-node-notready.md`](k3s-node-notready.md) — repeated
  tailnet hiccups can present as a NotReady before they look like an MTU
  problem.
