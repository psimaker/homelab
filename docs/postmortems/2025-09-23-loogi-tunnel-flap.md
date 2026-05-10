# Postmortem — 2025-09-23 — LOOGI Cloudflare Tunnel flapped for ~2h, p95 spiked, SLO budget burned ~30 %

## At a glance

| Field | Value |
| --- | --- |
| **Severity** | major |
| **Duration** | 02:14 |
| **Customer impact** | LOOGI users hitting `loogi.ch` saw intermittent 522s and ~3-second page loads during the affected window. Estimated ~62 % of search traffic over those 2 hours got at least one degraded request. |
| **Detected via** | `LoogiLatencyP95Exceeded` (warning) → `LoogiAvailabilityHighBurnFast` (critical) ntfy push |
| **Detected at** | 2025-09-23 21:42 UTC (Saturday evening, roughly half the impact window had already happened by the time the warning escalated to a page) |
| **Resolved at** | 2025-09-23 23:56 UTC |

## Timeline (UTC)

- **21:30** — `LoogiLatencyP95Exceeded` warning starts firing in
  Alertmanager. Goes to the `homelab-warnings` ntfy topic, which is digest,
  so I don't get pushed.
- **21:42** — `LoogiAvailabilityHighBurnFast` (fast-burn, 14.4×) trips. ntfy
  push to phone.
- **21:44** — I open the laptop, hit the loogi Grafana dashboard. p95 is
  at 4.2 s (budget 800 ms), error rate is 6 %.
- **21:46** — `curl https://loogi.ch/healthz` from the laptop: 200 OK. Try
  again 30 seconds later: hangs, eventually 522.
- **21:49** — `kubectl -n cloudflared logs ds/cloudflared --tail=200`. See
  repeating cycles of `INF Connection terminated error="connection
  closed by remote"` followed by `INF Updated to new configuration` ~30 s
  later. Tunnel is flapping.
- **21:52** — Check
  [cloudflarestatus.com](https://www.cloudflarestatus.com/) — green.
  Suspect our side.
- **21:55** — `cloudflared --version` against the running pod: `2024.9.1`.
  No recent upgrade, so probably not a cloudflared regression.
- **22:04** — Try doubling the cloudflared replica count to 2 (was 1).
  `kubectl -n cloudflared scale ds cloudflared --replicas=2` — no, it's
  a DaemonSet, that doesn't work like that. Edit the HelmRelease values
  to remove the `nodeSelector` so it can run on airbase too. Push.
- **22:09** — Flux reconciles, second cloudflared pod comes up on airbase.
  Symptom doesn't change — both tunnels are flapping at the same time.
  This rules out a node-specific issue and tells me it's something about
  the cloudflared ↔ Cloudflare-edge link itself.
- **22:18** — Search "cloudflared keepalive idle timeout flap". Get to a
  Cloudflare community thread describing the same symptom on home ISPs
  with aggressive idle-timeout NAT. Default `KEEPALIVE_INTERVAL=30s` is
  too long for ISPs that drop idle UDP flows after ~60 s — by the time
  the next keepalive goes out, the NAT translation has been recycled.
- **22:31** — Edit `kubernetes/infrastructure/cloudflared/values.yaml`,
  set `extraArgs: ["--keepalive-interval=15s"]`. Push.
- **22:34** — Flux reconciles, cloudflared rolls. Watching `tail -f` of
  the logs: no "Connection terminated" for the next 30 minutes.
- **22:50** — p95 has dropped back to baseline (~340 ms). Error rate at
  0.4 %.
- **23:56** — Confirm the burn-rate alerts have all resolved in
  Alertmanager. SLO error-budget panel shows 31.4 % of the 28-day budget
  consumed by this incident. I close the laptop.

## Summary

Cloudflare Tunnel for `loogi.ch` flapped intermittently for ~2 hours on
Saturday evening. Each flap was a 30-second outage from the user's
perspective. p95 latency briefly hit 4 seconds and the availability SLO
burned ~30 % of its 28-day budget in one event. Root cause was that
`cloudflared` was running with the default `keepalive-interval=30s`, which
is longer than my home ISP's NAT idle-timeout for UDP flows. When traffic
dropped low (Saturday evening — search volume lulls outside European
working hours), the tunnel's UDP path went idle, the ISP recycled the NAT
mapping, and cloudflared had to re-establish. Fix was lowering the
keepalive to 15 s and running a second cloudflared replica for redundancy.

## Impact

- ~2 hours of intermittent degradation on `loogi.ch`. Of the ~14 k search
  requests served in that window, an estimated 8.7 k saw at least one
  degraded retry. ~280 requests received a 522 with no retry.
- 31.4 % of the 28-day availability SLO budget was consumed. Latency
  budget burn was smaller (~9 %).
- No data loss. No downstream service affected.
- Detection was slow: the warning fired at 21:30 but I wasn't paged until
  21:42. By then half the incident window had already occurred.

## Root cause

The Cloudflare Tunnel between the home cluster and Cloudflare's edge runs
over QUIC by default, which is UDP-based. UDP "connection" tracking on
home routers (and on consumer ISPs more broadly) is timer-driven: a flow
that goes idle for longer than the configured timeout (typically 30–120 s
on consumer kit) gets evicted from the NAT table. The next packet from
either end no longer matches a translation entry, and the path effectively
breaks until cloudflared notices and re-establishes.

cloudflared has a `--keepalive-interval` flag exactly for this purpose.
The default is 30 s. My ISP appears to have an idle-timeout closer to 60 s
on the WAN side, which sounds fine — but with one keepalive every 30 s,
clock skew plus packet loss meant we crossed the 60 s gap regularly enough
to trigger flaps under low traffic.

The reason this hadn't happened earlier is that during the day the search
traffic itself acts as a keepalive. The tunnel is exercised constantly. On
Saturday evening, search volume dropped to ~3 requests per minute, leaving
multi-minute gaps in actual user traffic. The keepalive *should* have
filled those gaps, but didn't reliably with the 30 s interval.

The deeper cause is that I provisioned cloudflared from the upstream
chart with default values and never tuned it for a home-ISP environment.
The chart docs do mention the keepalive flag but it wasn't on my radar.

## What went well

- The two-window multi-burn-rate alert ladder behaved exactly as designed.
  The latency warning fired first at 21:30 (slow burn), then the
  availability alert escalated to a page at 21:42 once the impact passed
  the fast-burn threshold. I'd seen the warning in the digest in the
  morning and should've acted on it then, but the architecture worked.
- `kubectl logs ds/cloudflared` made the symptom (`Connection terminated`)
  obvious within 5 minutes of getting on the keyboard.
- The fix (one line in `values.yaml`) shipped via the normal GitOps path
  — no `kubectl edit`, no out-of-band patches, no drift.

## What went wrong

- I ran `cloudflared` as a single-replica DaemonSet pinned to the edge
  node. Even after the fix, that's a single point of failure for
  `loogi.ch`. Adding a second replica during the incident was the right
  move but should have been the default.
- The slow-burn warning is the right signal but goes to the digest topic.
  By the time it escalated to fast-burn paging, half the incident
  window had passed. I should consider routing slow-burn warnings to ntfy
  push for the public SLO target only.
- Searching the Cloudflare community for the symptom took longer than
  reading the cloudflared docs would have. I should keep a quick-reference
  list of "known knobs that affect production" in the runbook itself.

## What we got lucky on

- It was Saturday evening. Search volume was low both because of the
  outage *and* because Saturday evening always has low volume. If this
  had happened mid-week during European business hours, the absolute
  number of affected users would have been ~5x higher.
- The SLO budget had been near-pristine before this incident (only ~3 %
  consumed in the prior 26 days). After burning 31 %, we still had ~67 %
  of budget for the rest of the window. If this had happened with an
  already-stressed budget, we'd have had to declare formal degraded mode.
- The tunnel flap pattern was repeating (vs. one big outage), which made
  it easier to confirm the fix in real time — every 30 seconds I got a
  fresh observation.

## Action items

- [x] **me** — Lower `cloudflared` keepalive interval to 15 s — 2025-09-23 — landed in commit `a3f291`.
- [x] **me** — Run cloudflared as 2 replicas across both nodes — 2025-09-23 — landed in commit `c81e04`.
- [x] **me** — Add `cloudflared_tunnel_active_streams == 0` Prometheus alert (`CloudflaredTunnelDead`, 2 m) — 2025-09-26 — alert now in `kubernetes/infrastructure/cloudflared/alerts.yaml`.
- [x] **me** — Document keepalive interval as a known cause in
      [`loogi-availability.md`](../runbooks/loogi-availability.md) — 2025-09-28.
- [ ] **me** — Decide whether to route LOOGI slow-burn warnings to push (not just digest) — 2026-Q3 — open in [git.psimaker.org/umut.erdem/homelab#142](https://git.psimaker.org/umut.erdem/homelab/issues/142).
- [x] **me** — Renovate guard so a chart bump cannot reset the keepalive env var — 2025-10-04 — added `regexManagers` rule that watches the `extraArgs` block.

## Lessons

The default values of upstream Helm charts are calibrated for cloud
networks, not for residential ISPs. cloudflared keepalive at 30 s is fine
behind enterprise NAT or no NAT; behind consumer-grade NAT it is asking
for trouble. I now treat any chart that runs over UDP-from-home as
"defaults are not safe defaults" and read the operational tuning section
of the upstream docs before deploying.

A second lesson on alerting: the multi-window multi-burn-rate ladder is
correct in shape but my routing was wrong. Slow burn going only to digest
means real degradation can run for 12+ minutes before I see it. Routing
the public-SLO slow-burn to push is a small cost (slightly more pages,
sometimes for transient noise) for a much-faster-detection win on the one
service that has a real SLO.

A third lesson is structural: a single-replica anything fronting a public
SLO target is a default I shouldn't accept anywhere. The cost of running
two cloudflared pods is essentially zero — a few MB of RAM per replica.
The cost of "I noticed the SPOF only after it bit me" was 30 % of a
month's budget.
