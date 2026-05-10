data "cloudflare_zone" "this" {
  for_each = local.zones
  filter   = { name = each.value }
}

# Edge-node A/AAAA — bypasses the tunnel because Tailscale + ACME need
# direct reachability of the public IPs.
resource "cloudflare_dns_record" "edge_a" {
  zone_id = data.cloudflare_zone.this["psimaker_org"].zone_id
  name    = "edge.psimaker.org"
  type    = "A"
  content = module.edge.ipv4
  proxied = false
  ttl     = 300
}

resource "cloudflare_dns_record" "edge_aaaa" {
  zone_id = data.cloudflare_zone.this["psimaker_org"].zone_id
  name    = "edge.psimaker.org"
  type    = "AAAA"
  content = module.edge.ipv6
  proxied = false
  ttl     = 300
}

# Single tunnel backs every public Tier-1 hostname.
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab_prod" {
  account_id    = var.cloudflare_account_id
  name          = "homelab-prod"
  tunnel_secret = base64encode(random_password.tunnel_secret.result)
  config_src    = "cloudflare"
}

# Pocket-ID as the OIDC IdP for Cloudflare Access on admin services.
resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = var.cloudflare_account_id
  name       = "pocket-id"
  type       = "oidc"

  config = {
    client_id     = var.pocket_id_client_id
    client_secret = var.pocket_id_client_secret
    auth_url      = "${local.pocket_id_issuer}/authorize"
    token_url     = "${local.pocket_id_issuer}/token"
    certs_url     = "${local.pocket_id_issuer}/jwks"
    scopes        = ["openid", "email", "profile"]
    email_claim   = "email"
    pkce_enabled  = true
  }
}

module "app" {
  for_each = local.hostnames
  source   = "../../modules/cloudflare-app"

  account_id = var.cloudflare_account_id
  zone_id    = data.cloudflare_zone.this[each.value.zone].zone_id
  hostname   = each.value.fqdn
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab_prod.id
  service    = var.tunnel_origin_service

  access_policy = each.value.auth ? {
    name             = each.key
    session_duration = "24h"
    idp_ids          = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
    include_emails   = var.admin_emails
  } : null
}

# Tunnel ingress config — composed from each app's ingress_rule output.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab_prod" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab_prod.id

  config = {
    ingress = concat(
      [for m in module.app : m.ingress_rule],
      [{ service = "http_status:404" }],
    )
  }
}

# Page rules — aggressive cache for the CDN host, bypass cache on the apex.
resource "cloudflare_page_rule" "cdn_aggressive" {
  zone_id  = data.cloudflare_zone.this["loogi_ch"].zone_id
  target   = "cdn.loogi.ch/*"
  priority = 1
  status   = "active"

  actions = {
    cache_level    = "cache_everything"
    edge_cache_ttl = 2592000 # 30 days
  }
}

resource "cloudflare_page_rule" "apex_bypass" {
  zone_id  = data.cloudflare_zone.this["loogi_ch"].zone_id
  target   = "loogi.ch/*"
  priority = 2
  status   = "active"

  actions = {
    cache_level = "bypass"
  }
}
