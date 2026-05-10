# `cloudflare-app`

DNS + Tunnel ingress + optional Zero-Trust gating for one hostname.

The aggregating root collects the `ingress_rule` outputs from each instance
and composes them into a single `cloudflare_zero_trust_tunnel_cloudflared_config`
resource — one tunnel config per tunnel, many hostnames.

## Inputs

| Name              | Type     | Default | Notes |
| ----------------- | -------- | ------- | ----- |
| `account_id`      | string   | —       | |
| `zone_id`         | string   | —       | Output of `cloudflare_zone` data source |
| `hostname`        | string   | —       | |
| `tunnel_id`       | string   | —       | The tunnel that backs this hostname |
| `service`         | string   | —       | Origin URL (e.g. `http://cloudflared.cloudflared.svc.cluster.local:80`) |
| `proxied`         | bool     | `true`  | Cloudflare proxy on/off |
| `access_policy`   | object   | `null`  | Set to gate the hostname behind Cloudflare Access |

## Outputs

| Name             | Description                                      |
| ---------------- | ------------------------------------------------ |
| `hostname`       | Echo of input                                    |
| `ingress_rule`   | `{ hostname, service }` for tunnel config        |
| `application_id` | Access application ID (null if unauthenticated)  |

## Example — public site, no auth

```hcl
module "loogi" {
  source = "../../modules/cloudflare-app"

  account_id = var.cloudflare_account_id
  zone_id    = data.cloudflare_zone.loogi_ch.zone_id
  hostname   = "loogi.ch"
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab_prod.id
  service    = "http://cloudflared.cloudflared.svc.cluster.local:80"
}
```

## Example — admin service, gated by Pocket-ID OIDC

```hcl
module "grafana" {
  source = "../../modules/cloudflare-app"

  account_id = var.cloudflare_account_id
  zone_id    = data.cloudflare_zone.psimaker_org.zone_id
  hostname   = "grafana.psimaker.org"
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab_prod.id
  service    = "http://cloudflared.cloudflared.svc.cluster.local:80"

  access_policy = {
    name             = "grafana-admin"
    session_duration = "24h"
    idp_ids          = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
    include_emails   = ["umut.erdem@protonmail.com"]
  }
}
```
