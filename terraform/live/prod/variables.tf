variable "hcloud_token" {
  description = "Hetzner Cloud API token with read-write scope on the project."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Scope: Zone:Read+Edit, DNS:Edit, Tunnel:Edit, Access:Edit on the relevant zones."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "b2_application_key_id" {
  description = "Master B2 application key ID for provisioning sub-keys."
  type        = string
  sensitive   = true
}

variable "b2_application_key" {
  description = "Master B2 application key secret."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Operator SSH public key authorised on the edge node."
  type        = string
}

variable "admin_allowlist" {
  description = "CIDRs permitted to reach 22/tcp on edge."
  type        = list(string)
}

variable "tunnel_origin_service" {
  description = "Origin URL the Cloudflare Tunnel forwards to (cloudflared ClusterIP service)."
  type        = string
  default     = "http://cloudflared.cloudflared.svc.cluster.local:80"
}

variable "pocket_id_metadata_url" {
  description = "Pocket-ID OIDC discovery URL for the Cloudflare Access IdP."
  type        = string
}

variable "pocket_id_client_id" {
  description = "OIDC client ID issued by Pocket-ID for Cloudflare Access."
  type        = string
  sensitive   = true
}

variable "pocket_id_client_secret" {
  description = "OIDC client secret issued by Pocket-ID for Cloudflare Access."
  type        = string
  sensitive   = true
}

variable "admin_emails" {
  description = "Operator emails permitted by Cloudflare Access on admin hostnames."
  type        = list(string)
}
