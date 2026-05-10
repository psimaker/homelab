output "bucket_id" {
  description = "B2 bucket ID."
  value       = b2_bucket.this.bucket_id
}

output "bucket_name" {
  description = "B2 bucket name."
  value       = b2_bucket.this.bucket_name
}

output "key_id" {
  description = "ID of the bucket-scoped application key."
  value       = b2_application_key.this.application_key_id
  sensitive   = true
}

output "key_secret" {
  description = "Secret of the bucket-scoped application key. Surface to SOPS."
  value       = b2_application_key.this.application_key
  sensitive   = true
}
