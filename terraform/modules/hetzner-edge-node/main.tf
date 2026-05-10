locals {
  labels = merge({ role = "edge", managed-by = "opentofu" }, var.labels)

  # Tailscale direct conns (41641/udp): falls back to DERP if blocked anyway.
  firewall_rules = [
    { protocol = "tcp", port = "22", source_ips = var.admin_allowlist },
    { protocol = "tcp", port = "80", source_ips = ["0.0.0.0/0", "::/0"] },
    { protocol = "tcp", port = "443", source_ips = ["0.0.0.0/0", "::/0"] },
    { protocol = "udp", port = "41641", source_ips = ["0.0.0.0/0", "::/0"] },
  ]
}

resource "hcloud_ssh_key" "this" {
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
  labels     = local.labels
}

resource "hcloud_firewall" "this" {
  name   = "${var.name}-fw"
  labels = local.labels

  dynamic "rule" {
    for_each = local.firewall_rules
    content {
      direction  = "in"
      protocol   = rule.value.protocol
      port       = rule.value.port
      source_ips = rule.value.source_ips
    }
  }
}

resource "hcloud_server" "this" {
  name         = var.name
  location     = var.location
  server_type  = var.server_type
  image        = var.image
  ssh_keys     = [hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.this.id]
  user_data    = var.user_data
  labels       = local.labels

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = var.network_id
    ip         = var.private_ip
  }
}
