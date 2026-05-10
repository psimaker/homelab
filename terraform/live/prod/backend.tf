# Hetzner Object Storage as an S3-compatible backend with native locking.
# OpenTofu 1.10+ implements `use_lockfile = true`, replacing the DynamoDB
# pattern. The bucket itself is created once by hand, then re-imported and
# managed by this same configuration (see hetzner.tf -> aws_s3_bucket.state).

terraform {
  backend "s3" {
    bucket = "psimaker-tofu-state"
    key    = "live/prod/terraform.tfstate"
    region = "fsn1"

    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    use_lockfile                = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
