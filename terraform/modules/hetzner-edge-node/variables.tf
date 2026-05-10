variable "name" {
  description = "Server name; also used as the Hetzner Cloud resource label."
  type        = string
}

variable "location" {
  description = "Hetzner datacenter location (e.g. fsn1, nbg1, hel1)."
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Hetzner server type. CX22 is the smallest x86 shared-vCPU model."
  type        = string
  default     = "cx22"
}

variable "image" {
  description = "OS image slug. Debian 12 is the only supported baseline."
  type        = string
  default     = "debian-12"
}

variable "ssh_key_name" {
  description = "Name to register the SSH key under in Hetzner Cloud."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH-format public key that will be authorised for the umo user."
  type        = string
}

variable "admin_allowlist" {
  description = "CIDRs allowed to reach 22/tcp on the public interface."
  type        = list(string)
}

variable "network_id" {
  description = "ID of the Hetzner private network this server attaches to."
  type        = string
}

variable "private_ip" {
  description = "Static IP to assign on the private network."
  type        = string
}

variable "user_data" {
  description = "Cloud-init user-data document. Rendered by the caller."
  type        = string
}

variable "labels" {
  description = "Extra labels merged onto every resource."
  type        = map(string)
  default     = {}
}
