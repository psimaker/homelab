# `b2-restic-bucket`

One private Backblaze B2 bucket plus an application key scoped to that
bucket only. Restic-tier lifecycle rules are passed through verbatim.

## Inputs

| Name               | Type                                             | Default | Notes |
| ------------------ | ------------------------------------------------ | ------- | ----- |
| `name`             | string                                           | —       | Globally-unique bucket name |
| `lifecycle_rules`  | list(object)                                     | `[]`    | See shape below |
| `key_name`         | string                                           | —       | Display name for the key |
| `key_capabilities` | list(string)                                     | restic-default | Override only if you know why |

`lifecycle_rules` shape:

```hcl
{
  file_name_prefix              = "data/"
  days_from_uploading_to_hiding = 365
  days_from_hiding_to_deleting  = 1
}
```

## Outputs

| Name           | Description                        |
| -------------- | ---------------------------------- |
| `bucket_id`    | B2 bucket ID                       |
| `bucket_name`  | Echo of `var.name`                 |
| `key_id`       | Application key ID (sensitive)     |
| `key_secret`   | Application key secret (sensitive) |

## Example

```hcl
module "restic_critical" {
  source = "../../modules/b2-restic-bucket"

  name     = "psimaker-restic-critical"
  key_name = "restic-critical-rw"

  lifecycle_rules = [{
    file_name_prefix              = ""
    days_from_uploading_to_hiding = 0
    days_from_hiding_to_deleting  = 1
  }]
}
```

The key secret is shown exactly once on creation. Pipe it straight into a
SOPS-encrypted file (e.g. `sops kubernetes/.../restic.sops.yaml`) — never
into plaintext state.
