# `hetzner-edge-node`

One Hetzner Cloud server, one firewall, one SSH key, one private-network
attachment. Opinionated towards Debian 12 + cloud-init.

## Inputs

| Name              | Type           | Default     | Notes |
| ----------------- | -------------- | ----------- | ----- |
| `name`            | string         | —           | Server hostname and label prefix |
| `location`        | string         | `fsn1`      | Hetzner DC slug |
| `server_type`     | string         | `cx22`      | Smallest shared-vCPU AMD type |
| `image`           | string         | `debian-12` | |
| `ssh_key_name`    | string         | —           | Hetzner SSH key resource name |
| `ssh_public_key`  | string         | —           | OpenSSH public key |
| `admin_allowlist` | list(string)   | —           | CIDRs allowed on 22/tcp |
| `network_id`      | string         | —           | Pre-existing `hcloud_network` ID |
| `private_ip`      | string         | —           | Static IP on that network |
| `user_data`       | string         | —           | Cloud-init document |
| `labels`          | map(string)    | `{}`        | Merged onto every resource |

## Outputs

| Name           | Description                       |
| -------------- | --------------------------------- |
| `id`           | Server ID                         |
| `ipv4`         | Public IPv4                       |
| `ipv6`         | Public IPv6                       |
| `private_ipv4` | IP on the private network         |
| `firewall_id`  | Attached firewall ID              |

## Firewall posture

| Direction | Proto | Port | Source                | Reason                  |
| --------- | ----- | ---- | --------------------- | ----------------------- |
| in        | tcp   | 22   | `var.admin_allowlist` | SSH from operator(s)    |
| in        | tcp   | 80   | `0.0.0.0/0`, `::/0`   | HTTP → ACME, redirect   |
| in        | tcp   | 443  | `0.0.0.0/0`, `::/0`   | HTTPS via Cloudflare    |
| in        | udp   | 41641| `0.0.0.0/0`, `::/0`   | Tailscale direct conns  |

Everything else implicitly denies — Hetzner firewalls are deny-by-default
on `in`. `out` is unrestricted.

## Example

```hcl
module "edge" {
  source = "../../modules/hetzner-edge-node"

  name            = "edge-prod-01"
  ssh_key_name    = "umo-laptop"
  ssh_public_key  = var.ssh_public_key
  admin_allowlist = var.admin_allowlist
  network_id      = hcloud_network.cluster.id
  private_ip      = "10.20.1.10"
  user_data       = file("${path.module}/cloud-init.yaml")
}
```
