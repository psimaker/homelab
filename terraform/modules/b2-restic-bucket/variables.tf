variable "name" {
  description = "Globally-unique B2 bucket name."
  type        = string
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules in B2 native shape. Each entry sets an upload-prefix and
    file-age thresholds for hiding/deletion. Empty list disables lifecycle.
  EOT
  type = list(object({
    file_name_prefix              = string
    days_from_uploading_to_hiding = optional(number)
    days_from_hiding_to_deleting  = optional(number)
  }))
  default = []
}

variable "key_name" {
  description = "Name of the application key restricted to this bucket."
  type        = string
}

variable "key_capabilities" {
  description = "B2 capabilities granted to the application key."
  type        = list(string)
  default = [
    "listBuckets",
    "listFiles",
    "readFiles",
    "shareFiles",
    "writeFiles",
    "deleteFiles",
  ]
}
