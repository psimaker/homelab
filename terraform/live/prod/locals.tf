locals {
  edge_name = "edge-prod-01"

  # Private network sized for the cluster + future expansion.
  network_cidr = "10.20.0.0/16"
  subnet_cidr  = "10.20.1.0/24"
  edge_private = "10.20.1.10"

  zones = {
    loogi_ch     = "loogi.ch"
    psimaker_org = "psimaker.org"
  }

  # Hostnames the tunnel serves. Single source of truth for cloudflare.tf.
  hostnames = {
    loogi = {
      zone = "loogi_ch"
      fqdn = "loogi.ch"
      auth = false
    }
    pocket_id = {
      zone = "psimaker_org"
      fqdn = "id.psimaker.org"
      auth = false # Pocket-ID issues its own UI session
    }
    headscale = {
      zone = "psimaker_org"
      fqdn = "hs.psimaker.org"
      auth = false # Tailscale clients can't carry Access cookies
    }
  }

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
  })

  pocket_id_issuer = trimsuffix(var.pocket_id_metadata_url, "/.well-known/openid-configuration")
}
