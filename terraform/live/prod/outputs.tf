output "edge_ipv4" {
  description = "Public IPv4 of the edge node."
  value       = module.edge.ipv4
}

output "edge_ipv6" {
  description = "Public IPv6 of the edge node."
  value       = module.edge.ipv6
}

output "edge_private_ipv4" {
  description = "Edge-node IP on the Hetzner private network."
  value       = module.edge.private_ipv4
}

output "tunnel_id" {
  description = "Cloudflare Tunnel ID. Consumed by the cloudflared HelmRelease."
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab_prod.id
}

output "state_bucket" {
  description = "Hetzner Object Storage bucket holding OpenTofu state."
  value       = hcloud_storage.tofu_state.name
}

output "loki_bucket" {
  description = "Hetzner Object Storage bucket for Loki chunks."
  value       = hcloud_storage.loki.name
}

output "restic_critical_bucket" {
  description = "B2 bucket for the critical-tier restic repository."
  value       = module.restic_critical.bucket_name
}

output "restic_deep_bucket" {
  description = "B2 bucket for the deep-archive restic repository."
  value       = module.restic_deep.bucket_name
}
