output "id" {
  description = "Hetzner Cloud server ID."
  value       = hcloud_server.this.id
}

output "ipv4" {
  description = "Public IPv4 address."
  value       = hcloud_server.this.ipv4_address
}

output "ipv6" {
  description = "Public IPv6 address."
  value       = hcloud_server.this.ipv6_address
}

output "private_ipv4" {
  description = "Static IP on the attached private network."
  value       = var.private_ip
}

output "firewall_id" {
  description = "ID of the firewall attached to this server."
  value       = hcloud_firewall.this.id
}
