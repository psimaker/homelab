# Runbook — LOOGI availability burning error budget

> **Triggers:** `LoogiAvailabilityHighBurnFast` (14.4× burn over 1h/5m windows)
> or `LoogiAvailabilityBudgetExhausted` (28-day budget < 0%).
> **Severity:** critical (paging via ntfy `homelab-critical`)
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. `curl -fsS -o /dev/null -w '%{http_code} %{time_total}\n' https://loogi.ch/healthz` — does it answer at all?
2. `kubectl -n loogi get pods` — are the loogi and Valkey pods `Running 1/1`?
3. `kubectl -n cloudflared get ds cloudflared` — both replicas `READY 2/2`?
4. If any "no": jump to **Investigate** below. If all green and 200s are flowing: it was probably a brief CDN blip — silence the alert for 15m and watch the SLO error-budget panel for another spike.

## Context

`loogi.ch` is the only workload in this homelab with a published SLO and it's
the public-facing one. The availability SLO is **99.5 % over 28 days** — which
is roughly 3h36m of allowed downtime per window. The fast-burn alert
(14.4× burn rate over a 1h short window backed by a 5m short window, the
Google SRE multi-window pattern) fires when we are on track to spend 2 % of the
monthly budget in one hour. That's the page. The slow-burn (`6×` over
6h/30m) fires as a warning.

Architecturally the request path is:

```
user → Cloudflare edge → Cloudflare Tunnel → cloudflared (DS, edge node)
     → Traefik IngressRoute → Service `loogi` → Pod (loogi/SearXNG)
     → Valkey (cache) and the public search engines (Google, Bing, DDG, ...)
```

Anything in that chain can cause an availability dip. The runbook walks the
chain.

## Investigate

### Is the request reaching us at all?

```
curl -v https://loogi.ch/healthz
# expect: HTTP/2 200, body "ok\n", served from cf-cache=DYNAMIC
```

If you get a 5xx with `cf-ray` set but no upstream reply, the tunnel is
flapping (jump to cloudflared section). If you get a 521/522, cloudflared
is unreachable from the Cloudflare edge.

### Cloudflared pod and tunnel

```
kubectl -n cloudflared get ds/cloudflared -o wide
kubectl -n cloudflared logs ds/cloudflared --tail=200
kubectl -n cloudflared logs ds/cloudflared --previous --tail=200   # if it just restarted
```

Look for `Connection terminated` / `Lost connection`. The tunnel uses
`KEEPALIVE_INTERVAL=15s` (we lowered it after the 2025-09-23 incident — see
the postmortem); if you see keepalive timeouts repeatedly, suspect upstream
Cloudflare edge or the Hetzner network. Cross-check
[cloudflarestatus.com](https://www.cloudflarestatus.com/).

Active streams:

```
# from the Prometheus UI on the tailnet
cloudflared_tunnel_active_streams
# the alert "CloudflaredTunnelDead" fires if this is 0 for >2m
```

### Traefik

```
kubectl -n traefik get pods
kubectl -n traefik logs deploy/traefik --tail=200 | grep -i loogi
kubectl -n traefik get ingressroute -A | grep loogi
```

A useful one-liner for the live request rate hitting Traefik:

```
sum by (entrypoint, code) (rate(traefik_entrypoint_requests_total{entrypoint="websecure"}[2m]))
```

A flat-line of zero when the alert says we're seeing 5xx means the failures
are happening *before* Traefik (i.e. the tunnel side).

### loogi pod itself

```
kubectl -n loogi get pods -o wide
kubectl -n loogi describe pod -l app.kubernetes.io/name=loogi | tail -50
kubectl -n loogi logs deploy/loogi --tail=300
```

Health endpoint from inside the cluster (skips the tunnel):

```
kubectl -n loogi run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -sS http://loogi.loogi.svc.cluster.local/healthz
```

If this is 200 and `https://loogi.ch/healthz` is 5xx, the problem is between
Traefik and the public.

### Valkey (cache)

If Valkey is unreachable, every search request becomes a cold lookup against
upstream engines and p95 latency *plus* error rate explode together.

```
kubectl -n loogi exec deploy/valkey -- valkey-cli ping     # expect: PONG
kubectl -n loogi exec deploy/valkey -- valkey-cli info memory | grep used_memory_human
kubectl -n loogi top pod                                   # OOM signal
```

### CDN cache hit rate

Open the loogi Grafana dashboard, panel "Cloudflare cache hit ratio". Normal
is around 35–45 % (most queries are user-specific so we don't cache much). If
this fell to single digits, suspect a cache purge or a bad `Cache-Control`
header in a recent loogi release.

## Common causes

In rough order of how often I've actually hit them:

- **A SearXNG engine is stalling.** One of the upstream engines (most often
  Bing, occasionally Brave) starts taking >10s to respond. SearXNG's per-engine
  timeout is 5s, so requests succeed — but the user-perceived page-load goes
  past the SLO threshold and the multi-burn alert that's secondary on this
  runbook (`LoogiLatencyP95Exceeded`) trips first. See
  [`loogi-latency-p95.md`](loogi-latency-p95.md). The two alerts often fire
  together because slow requests amplify retry pressure.
- **cloudflared restart with default keepalive.** Historical, fixed by the
  [2025-09-23 postmortem](../postmortems/2025-09-23-loogi-tunnel-flap.md).
  If you see this come back, check that the env var `KEEPALIVE_INTERVAL=15s`
  is still in `kubernetes/infrastructure/cloudflared/values.yaml` — Renovate
  has pulled chart bumps that reset env vars before.
- **Valkey OOM.** The HelmRelease pins `maxmemory: 256Mi` and `maxmemory-policy:
  allkeys-lru`. If someone (me) forgot to bump this after a query-volume jump,
  Valkey starts evicting hot keys and the engine cache turns into noise.
- **Cloudflare edge incident.** Rare but real. If
  [cloudflarestatus.com](https://www.cloudflarestatus.com/) shows yellow/red
  for the Falkenstein PoP, there's nothing to do but wait.
- **Tailscale path between edge and airbase.** Loogi runs on edge so this
  rarely matters for *availability* — it does for the latency runbook.

## Mitigation

### "Just stop the page"

```
# silence the burn-rate alert for 30 minutes while you investigate
amtool silence add --alertmanager.url=http://alertmanager.observability.svc:9093 \
  alertname=LoogiAvailabilityHighBurnFast --duration=30m \
  --comment="Triage in progress, see runbook"
```

### If cloudflared is stuck

```
kubectl -n cloudflared rollout restart ds/cloudflared
kubectl -n cloudflared rollout status ds/cloudflared --timeout=120s
```

The DaemonSet has 2 replicas (post-2025-09-23) and rolls one at a time, so
the surface stays up during the restart.

### If a SearXNG engine is the problem

Edit the engine list at
`kubernetes/apps/loogi/searxng-settings.yaml`, set the offending engine to
`disabled: true`, commit, push. Flux reconciles in <60s. Open a postmortem
only if the problem persisted >30m or the upstream incident is still live.

### Real fix

After the page is silenced and the symptom is gone, look at the SLO burn-down
in Grafana over the past 24h. If we've burned >30 % of the 28-day budget in
one event, this is a postmortem regardless of fix duration.

## Postmortem requirement

If this fires and the fix takes >30 min OR if user-facing 5xx exceeded 5 min,
open a postmortem in `docs/postmortems/` using `_template.md`.

## Related

- Architecture: [Observability](../architecture.md#observability),
  [TLS and reverse proxy](../architecture.md#tls-and-reverse-proxy)
- ADRs: [`0005-tls-zwei-issuer.md`](../adr/0005-tls-zwei-issuer.md)
- Past postmortems:
  [`2025-09-23-loogi-tunnel-flap.md`](../postmortems/2025-09-23-loogi-tunnel-flap.md)
- Sibling runbook: [`loogi-latency-p95.md`](loogi-latency-p95.md)
