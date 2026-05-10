output "hostname" {
  description = "The hostname this app serves."
  value       = var.hostname
}

output "ingress_rule" {
  description = "Ingress rule fragment for the tunnel config (hostname + service)."
  value = {
    hostname = var.hostname
    service  = var.service
  }
}

output "application_id" {
  description = "ID of the Zero-Trust Access application, or null if unauthenticated."
  value       = try(cloudflare_zero_trust_access_application.this[0].id, null)
}
