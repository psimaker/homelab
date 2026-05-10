variable "account_id" {
  description = "Cloudflare account ID that owns the zone and tunnel."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID this hostname lives in."
  type        = string
}

variable "hostname" {
  description = "Fully-qualified hostname this app is reachable at."
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare Tunnel ID that will serve this hostname."
  type        = string
}

variable "service" {
  description = "Origin URL the tunnel forwards to (e.g. http://traefik.traefik.svc.cluster.local:80)."
  type        = string
}

variable "proxied" {
  description = "Whether the DNS record is proxied through Cloudflare."
  type        = bool
  default     = true
}

variable "access_policy" {
  description = <<-EOT
    Optional Zero-Trust access configuration. Set to null to leave the host
    unauthenticated (e.g. for the public LOOGI front-end).
  EOT
  type = object({
    name             = string
    session_duration = string
    idp_ids          = list(string)
    include_emails   = optional(list(string), [])
  })
  default = null
}
