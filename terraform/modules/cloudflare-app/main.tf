resource "cloudflare_dns_record" "this" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = var.proxied
  ttl     = 1 # 1 = auto
  comment = "Managed by OpenTofu — cloudflare-app module"
}

# A tunnel config for the parent root_id is shared; this module contributes
# one ingress rule keyed on hostname. The aggregating root composes them.
resource "cloudflare_zero_trust_access_application" "this" {
  count = var.access_policy == null ? 0 : 1

  account_id                = var.account_id
  name                      = var.access_policy.name
  domain                    = var.hostname
  type                      = "self_hosted"
  session_duration          = var.access_policy.session_duration
  auto_redirect_to_identity = true
  allowed_idps              = var.access_policy.idp_ids
}

resource "cloudflare_zero_trust_access_policy" "this" {
  count = var.access_policy == null ? 0 : 1

  application_id = cloudflare_zero_trust_access_application.this[0].id
  account_id     = var.account_id
  name           = "${var.access_policy.name}-allow"
  decision       = "allow"
  precedence     = 1

  include = [
    for addr in coalesce(var.access_policy.include_emails, []) : {
      email = { email = addr }
    }
  ]
}
