# Runbook — cert renewal stuck

> **Triggers:** `CertManagerCertExpiringSoon` — fires when a Certificate has
> <14 days remaining. Warning at 14 d, critical at 7 d.
> **Severity:** warning then critical (paging at 7 d)
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. `kubectl get certificates -A` — which cert, expiring when, `READY=False`?
2. `kubectl describe certificate <name> -n <ns>` — read the `Events` table at the bottom.
3. `kubectl get clusterissuer -A` — both `letsencrypt-prod` and `letsencrypt-staging` `Ready=True`?
4. `kubectl logs -n cert-manager deploy/cert-manager --tail=200 | grep -i <fqdn>`

If any one of those screams at you, jump to the matching cause below.

## Context

Tier-1 TLS goes through cert-manager + Let's Encrypt **DNS-01** challenge,
solved against Cloudflare. Wildcard certs for `*.loogi.ch` and
`*.example.com` are issued and renewed automatically; Tier-2 (Compose) uses
Nginx Proxy Manager's built-in HTTP-01 ACME and is **not** in scope here —
[`docs/adr/0005-tls-zwei-issuer.md`](../adr/0005-tls-zwei-issuer.md) explains
the split.

DNS-01 needs cert-manager to write a `_acme-challenge.<host>` TXT record into
Cloudflare via API, wait for propagation, then ask LE to validate.

If renewal is stuck, the most likely reason is the API token. The second-most
is LE rate limiting. The third is DNS propagation racing the LE poll.

## Investigate

### Which cert and what does cert-manager say about it?

```
kubectl get certificates -A
# look for any with READY=False or short-time AGE going stale

kubectl describe certificate loogi-tls -n traefik
# scroll to the Events section
```

Useful fields:

- `Spec.SecretName` — where the renewed key+cert end up.
- `Status.Conditions[Ready].Reason` — `DoesNotExist`, `Failed`,
  `InProgress`, ...
- `Status.NextPrivateKeySecretName` — if set, a renewal is mid-flight.

### CertificateRequest and Order

```
kubectl get certificaterequests -n traefik
kubectl get orders -n traefik
kubectl get challenges -n traefik
```

`Order` is the LE-side state. `Challenge` is the per-domain DNS-01 work.
A challenge stuck at `pending` for more than ~5 min means cert-manager's
DNS verification poll is failing (it polls public DNS until the TXT record
is visible globally, then asks LE to validate).

Describe the stuck challenge:

```
kubectl describe challenge -n traefik
```

The `Events` here are the most useful lines in the whole investigation. You'll
typically see one of:

- `Presented challenge using DNS-01` — but no `DNS verification check passed`
  (TXT not propagating).
- `Error presenting challenge: ...` — Cloudflare API call failed (token
  problem).

### Cloudflare token

The token is held in `Secret/cloudflare-api-token` in `cert-manager`
namespace, referenced from the `ClusterIssuer`:

```
kubectl get clusterissuer letsencrypt-prod -o yaml | yq '.spec.acme.solvers'
kubectl get secret cloudflare-api-token -n cert-manager -o jsonpath='{.data.api-token}' \
  | base64 -d | head -c 8 ; echo
# expect a token prefix; if it's empty/garbled, the secret was rotated wrong
```

The token needs `Zone:DNS:Edit` and `Zone:Zone:Read` on both `loogi.ch` and
`example.com`. I rotate this token annually as part of Q1 housekeeping; if
the rotation drift hit a renewal cycle, this is your problem.

### Test the token directly

```
TOKEN=$(kubectl -n cert-manager get secret cloudflare-api-token -o jsonpath='{.data.api-token}' | base64 -d)
curl -s -H "Authorization: Bearer $TOKEN" 'https://api.cloudflare.com/client/v4/user/tokens/verify' | jq
# expect: "status":"active"
```

### LE rate limit?

LE allows 50 certs per registered domain per week and 5 duplicate certs per
week. A wildcard counts as one cert; if you've been retrying through staging
to debug something then accidentally hit prod, you can run out.

```
kubectl logs -n cert-manager deploy/cert-manager --tail=500 \
  | grep -E '429|rateLimited|too many'
```

### DNS propagation race

```
dig +short TXT _acme-challenge.loogi.ch @1.1.1.1
dig +short TXT _acme-challenge.loogi.ch @8.8.8.8
dig +short TXT _acme-challenge.loogi.ch @9.9.9.9
```

LE checks against multiple resolvers; if one major resolver is lagging on
Cloudflare's propagation, you'll see "DNS problem: NXDOMAIN looking up TXT".

## Common causes

- **Cloudflare API token rotated and not pushed through to the Secret.**
  Single most common. The fix is "regenerate the SOPS-encrypted Secret and
  let Flux apply it", not "kubectl edit secret" — the latter gets overwritten.
- **DNS propagation race.** Cloudflare normally propagates in seconds, but
  occasionally a record takes 60–90 s to be globally visible while LE is
  already polling. cert-manager retries on its own; only worry if it's
  failed three times in a row.
- **LE rate limit from staging→prod confusion.** Means you (I) used the
  wrong issuer name in a HelmRelease and burned through the prod allowance
  testing. Wait it out — limits are weekly.
- **cert-manager pod itself dead.** Rare. Usually a CRD upgrade fail after
  a minor bump that wasn't applied via Flux's HelmRelease properly.

## Mitigation

### Rotate the API token cleanly

1. Generate a new token in Cloudflare with the right zone scopes.
2. Update the SOPS-encrypted Secret manifest in
   `kubernetes/infrastructure/cert-manager/cloudflare-api-token.sops.yaml`.
3. Commit, push. Flux applies in <60 s.
4. Force a renewal by deleting the existing Order:
   ```
   kubectl delete order -n traefik <order-name>
   ```
   cert-manager creates a new Order, picks up the fresh token, and proceeds.

### Force-renew without waiting for the cron

```
cmctl renew -n traefik loogi-tls
# or, fallback if you don't have cmctl handy:
kubectl annotate certificate loogi-tls -n traefik \
  cert-manager.io/issue-temporary-certificate="true" --overwrite
```

### "Just stop the page" while you fix it

The 14-day warning isn't paging, but the 7-day critical is. Silence it for
24 h:

```
amtool silence add --alertmanager.url=http://alertmanager.observability.svc:9093 \
  alertname=CertManagerCertExpiringSoon --duration=24h \
  --comment="Manual rotation in progress"
```

### Emergency fallback: staging issuer

If LE prod is rate-limited and a cert is hours from expiring, swap the
`ClusterIssuer` reference temporarily to `letsencrypt-staging`. Browsers will
warn (the chain isn't trusted), but services come up. Only acceptable for
internal-only services. Never for `loogi.ch`.

## Postmortem requirement

If a cert ever actually expires (browsers showing warnings on a public
service), that's automatic postmortem territory. Pre-expiry renewal pain is
postmortem-worthy if it took >30 min to fix.

## Related

- Architecture: [TLS and reverse proxy](../architecture.md#tls-and-reverse-proxy)
- ADRs: [`0005-tls-zwei-issuer.md`](../adr/0005-tls-zwei-issuer.md)
