module "restic_critical" {
  source = "../../modules/b2-restic-bucket"

  name     = "psimaker-restic-critical"
  key_name = "restic-critical-rw"

  # Keep 6 monthly + 2 yearly. Restic prune handles snapshot retention; this
  # rule reaps anything that's been hidden (pruned) for 24h.
  lifecycle_rules = [{
    file_name_prefix              = ""
    days_from_uploading_to_hiding = 0
    days_from_hiding_to_deleting  = 1
  }]
}

module "restic_deep" {
  source = "../../modules/b2-restic-bucket"

  name     = "psimaker-restic-deep"
  key_name = "restic-deep-rw"

  # "Deep" archive: anything older than a year gets evicted entirely.
  lifecycle_rules = [{
    file_name_prefix              = ""
    days_from_uploading_to_hiding = 365
    days_from_hiding_to_deleting  = 1
  }]
}
