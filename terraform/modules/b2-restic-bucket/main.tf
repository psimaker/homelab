resource "b2_bucket" "this" {
  bucket_name = var.name
  bucket_type = "allPrivate"

  dynamic "lifecycle_rules" {
    for_each = var.lifecycle_rules
    content {
      file_name_prefix              = lifecycle_rules.value.file_name_prefix
      days_from_uploading_to_hiding = try(lifecycle_rules.value.days_from_uploading_to_hiding, null)
      days_from_hiding_to_deleting  = try(lifecycle_rules.value.days_from_hiding_to_deleting, null)
    }
  }
}

resource "b2_application_key" "this" {
  key_name     = var.key_name
  bucket_id    = b2_bucket.this.bucket_id
  capabilities = var.key_capabilities
}
