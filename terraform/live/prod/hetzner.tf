resource "hcloud_network" "cluster" {
  name     = "homelab-cluster"
  ip_range = local.network_cidr
  labels   = { managed-by = "opentofu" }
}

resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = local.subnet_cidr
}

module "edge" {
  source = "../../modules/hetzner-edge-node"

  name            = local.edge_name
  ssh_key_name    = "umo-operator"
  ssh_public_key  = var.ssh_public_key
  admin_allowlist = var.admin_allowlist
  network_id      = hcloud_network.cluster.id
  private_ip      = local.edge_private
  user_data       = local.cloud_init

  depends_on = [hcloud_network_subnet.cluster]
}

# Hetzner Object Storage buckets, managed via the dedicated `hcloud_storage`
# resource introduced in the hcloud ~> 1.50 provider.
#
# The state bucket itself is bootstrapped by hand the very first time, then
# imported into state on the second run:
#   tofu import hcloud_storage.tofu_state psimaker-tofu-state

resource "hcloud_storage" "tofu_state" {
  name     = "psimaker-tofu-state"
  location = "fsn1"
  type     = "object_storage"
  labels   = { purpose = "tofu-state", managed-by = "opentofu" }

  versioning = true # protect state files against accidental overwrite
}

resource "hcloud_storage" "loki" {
  name     = "psimaker-loki"
  location = "fsn1"
  type     = "object_storage"
  labels   = { purpose = "loki-chunks", managed-by = "opentofu" }

  # Loki TSDB compactor handles retention internally; this rule is a
  # belt-and-braces sweep for chunks orphaned past their compaction window.
  lifecycle_rule {
    id              = "expire-orphan-chunks"
    enabled         = true
    prefix          = "chunks/"
    expiration_days = 90
  }
}
