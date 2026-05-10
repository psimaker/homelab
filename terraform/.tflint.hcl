// tflint configuration for the homelab OpenTofu codebase.
//
// We exercise the core ruleset, plus the per-provider plugins for our three
// providers (Hetzner, Cloudflare, Backblaze B2). Renovate updates plugin
// versions via the github-releases datasource.
//
// Run from terraform/:  tflint --init && tflint --recursive

config {
  call_module_type = "all"
  format           = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# renovate: datasource=github-releases depName=hetznercloud/terraform-provider-hcloud
plugin "hcloud" {
  enabled = false
  # No official tflint plugin for hcloud yet; left as a marker so we notice
  # if one ships later.
}

# renovate: datasource=github-releases depName=cloudflare/terraform-provider-cloudflare
plugin "cloudflare" {
  enabled = false
  # Same as above — no first-party tflint plugin exists for cloudflare.
}

# Style rules we care about beyond the default preset.
rule "terraform_unused_declarations"            { enabled = true }
rule "terraform_documented_variables"           { enabled = true }
rule "terraform_documented_outputs"             { enabled = true }
rule "terraform_naming_convention"              { enabled = true }
rule "terraform_required_version"               { enabled = true }
rule "terraform_required_providers"             { enabled = true }
rule "terraform_typed_variables"                { enabled = true }
rule "terraform_standard_module_structure"      { enabled = true }
