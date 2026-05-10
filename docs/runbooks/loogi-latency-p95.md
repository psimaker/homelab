# Runbook — LOOGI p95 latency over budget

> **Triggers:** `LoogiLatencyP95Exceeded` — fast-burn (14.4× over 1h/5m) on the
> latency SLO ("≥ 95 % of `/search` requests under 800 ms").
> **Severity:** critical (paging) when fast-burn; warning when slow-burn (6× over 6h/30m).
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. Open the loogi Grafana dashboard, panel "p95 by route" — is the spike on `/search` only, or everywhere?
2. Open SearXNG `/stats` (linked below) — sort engines by `response_time` desc. Anything >2.5s?
3. `kubectl -n loogi exec deploy/valkey -- valkey-cli info stats | grep keyspace_hits` — hit ratio plummeted?
4. `kubectl top pod -n loogi` — is loogi or Valkey CPU-throttled?

If steps 1–3 fingered an engine: disable it (see Mitigation). Otherwise jump to Investigate.

## Context

Latency budget is 5 % of `/search` requests >800 ms over 28 days. Most user
sessions hit `/search` two or three times in quick succession, so latency
spikes hurt UX disproportionately and the burn-rate alert is sensitive on
purpose.

Where latency comes from, in order of usual contribution:

```
slowest engine in the parallel fan-out  >>>  Valkey RTT  >  Traefik+pod  >  CDN
```

SearXNG runs engines in parallel and returns once the configured timeout fires
or all engines reply. So **one slow engine sets the floor**, regardless of how
fast the others are.

## Investigate

### Which engine?

SearXNG exposes per-engine stats. From the operator laptop on the tailnet:

```
curl -s https://loogi.ch/stats | jq '.engines[] | {name, response_time, error_rate}' \
  | jq -s 'sort_by(.response_time) | reverse | .[0:5]'
```

Or the GUI: `https://loogi.ch/stats`. The columns I care about are
`response_time` (median) and `error_rate`. An engine with `error_rate > 5 %`
and rising response_time is rate-limiting us — common on Bing when we hit
their unofficial API too aggressively after a deploy.

### Valkey

```
kubectl -n loogi exec deploy/valkey -- valkey-cli info stats \
  | grep -E 'keyspace_(hits|misses)|expired_keys|evicted_keys'
```

Compute hit ratio quickly:

```
hits=$(kubectl -n loogi exec deploy/valkey -- valkey-cli info stats | awk -F: '/keyspace_hits/{print $2}' | tr -d '\r')
misses=$(kubectl -n loogi exec deploy/valkey -- valkey-cli info stats | awk -F: '/keyspace_misses/{print $2}' | tr -d '\r')
echo "scale=3; $hits / ($hits + $misses)" | bc
# expect: ~0.55 in steady state, drops below 0.30 after a deploy or a flush
```

After a fresh deploy of loogi the cache is cold for ~10 min and a latency
blip is *expected*. The alert window (5m short) is tuned to not fire from
a single deploy unless the blip extends.

### Network: edge ↔ engine

If engines look fine and Valkey is fine, the problem might be the egress path.
Hubble on the edge node:

```
hubble observe --pod loogi/loogi --type drop --since=10m
hubble observe --pod loogi/loogi --to-fqdn 'www.bing.com' --since=10m \
  -f -o json | jq '.flow.l7.http.latency_ns / 1e6' | sort -n | tail
```

### Per-engine SearXNG errors page

```
https://loogi.ch/stats/errors
```

This page lists the last N timeouts and exception types per engine. If you
see a wall of `httpx.ReadTimeout` from one engine, that's your culprit.

### Noisy neighbour on edge

Loogi runs on the edge node (CX22, 2 vCPU). One of the cluster system pods
having a CPU spike can starve loogi.

```
kubectl top pods --all-namespaces --sort-by=cpu | head -20
```

Anything pulling >800m on a 2-vCPU node is suspect. The usual offender is a
cert-manager renewal loop (which is fine — short) or, less commonly, the
prometheus-operator running a one-off compaction.

## Common causes

- **A search engine is rate-limiting us.** Bing first, Brave second, Google's
  unofficial frontend third. Symptom: that engine alone has `response_time`
  >2.5 s and `error_rate` climbing. Fix: disable temporarily (see Mitigation).
- **CPU pressure from a noisy neighbour on edge.** CX22 is 2 vCPU shared. A
  cert-manager DNS-01 verification loop running at the same time as a
  Renovate scrape can briefly throttle loogi's tornado workers.
- **Cold Valkey after a deploy.** Hit ratio drops, every request fans out to
  upstream engines, parallel-fanout floor latency dominates. Self-heals in
  ~10 min.
- **Tailscale path MTU oddness affecting egress to internet.** Indirect.
  Symptom: `httpx.ReadTimeout` against many engines simultaneously. See
  [`tailscale-mesh-mtu.md`](tailscale-mesh-mtu.md).
- **Cloudflare slow-path between user and edge PoP.** Rare; the latency SLO
  is computed at Traefik (server-side), so CDN-side slowness shouldn't
  trigger this alert. But check
  [cloudflarestatus.com](https://www.cloudflarestatus.com/) anyway.

## Mitigation

### Disable the offending engine fast

Edit the engines block in `kubernetes/apps/loogi/searxng-settings.yaml`:

```yaml
engines:
  - name: bing
    disabled: true   # 2026-05-10 — flapping, see runbook loogi-latency-p95
```

Commit and push. Flux reconciles in 60 s, the loogi pods roll. Re-enable in a
follow-up PR once the upstream is healthy. If it's a recurring engine, ADR
the timeout adjustment instead of leaving the comment.

### If Valkey is the bottleneck

Bump `maxmemory` in the values file. The chart default is 256Mi; production
is fine at 512Mi for current load. Don't go higher without a postmortem-style
"why" — the cache should be small to stay correct.

### If CPU pressure on edge

`kubectl describe node edge` and look at requests/limits totals. If we're
at 1.8/2.0 cores allocated, the next deploy needs to either go to airbase
(adjust `nodeAffinity`) or trigger an upgrade to CX32. There's a draft ADR
for that scenario in `docs/adr/draft-edge-sizing.md`.

### "Just stop the page"

```
amtool silence add --alertmanager.url=http://alertmanager.observability.svc:9093 \
  alertname=LoogiLatencyP95Exceeded --duration=30m --comment="triage"
```

## Postmortem requirement

If this fires and the fix takes >30 min OR if p95 stays out of budget for >5 min
of user-facing impact, open a postmortem.

## Related

- Architecture: [Observability — SLOs](../architecture.md#slos)
- Sibling runbook: [`loogi-availability.md`](loogi-availability.md)
- Network runbook: [`tailscale-mesh-mtu.md`](tailscale-mesh-mtu.md)
