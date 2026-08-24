# S3 module

Manages **one** S3 bucket and everything that belongs to it. Fan-out across
many buckets is the root module's job (`for_each`), which keeps state addresses
stable and the blast radius per bucket.

The module has no `provider` and no `backend` block — both are inherited from
the root in `../`.

## What it creates

| Always | Conditionally |
| --- | --- |
| `aws_s3_bucket` | `aws_kms_key` + alias (`create_kms_key`) |
| `aws_s3_bucket_ownership_controls` | `aws_s3_bucket_policy` (`attach_bucket_policy`) |
| `aws_s3_bucket_public_access_block` | `aws_s3_bucket_lifecycle_configuration` (`lifecycle_rules`) |
| `aws_s3_bucket_versioning` | `aws_s3_bucket_logging` (`logging`) |
| `aws_s3_bucket_server_side_encryption_configuration` | `aws_s3_bucket_cors_configuration` (`cors_rules`) |
| | `aws_s3_bucket_object_lock_configuration` (`object_lock_enabled`) |
| | `aws_s3_bucket_replication_configuration` + IAM role (`replication`) |

## Secure-by-default posture

Defaults are the safe ones; relaxing them is an explicit, reviewable change.

- **Public access blocked** on all four vectors (`block_public_access = true`).
- **ACLs disabled** via `BucketOwnerEnforced`.
- **Versioning on**.
- **SSE-KMS** with a dedicated, auto-rotated CMK and an S3 Bucket Key to keep
  KMS cost down.
- **Bucket policy denies** non-TLS requests and TLS below 1.2.
- **`force_destroy = false`** — Terraform will not silently empty a bucket.

The policy is attached with `depends_on` the public access block, so a bucket is
never briefly reachable while a policy lands.

## Usage

```hcl
module "s3" {
  source   = "./S3"
  for_each = var.s3_buckets

  bucket_name = local.s3_bucket_names[each.key]
  tags        = merge(each.value.tags, { Component = each.key })
  # ... remaining arguments
}
```

## Notable inputs

| Name | Default | Notes |
| --- | --- | --- |
| `bucket_name` | — | Required. Validated against the S3 naming rules. |
| `sse_algorithm` | `aws:kms` | `AES256` for log-delivery targets, which cannot use a customer CMK. |
| `create_kms_key` | `true` | Ignored when `kms_key_arn` is supplied. |
| `deny_unencrypted_uploads` | `false` | Denies only a *contradicting* SSE header; a missing header still falls through to default encryption. |
| `object_lock_enabled` | `false` | Immutable after bucket creation. |
| `replication` | `null` | Requires `versioning_enabled = true`; enforced by a precondition. |
| `additional_policy_documents` | `[]` | Merged into the managed policy — cross-account grants go here. |

## Gotchas

- **Log-delivery buckets must use `AES256`.** S3 server access log delivery
  cannot write into a bucket encrypted with a customer-managed CMK.
- **`mfa_delete` cannot be toggled by Terraform.** It requires the bucket owner
  root user with an active MFA device; the variable exists for parity only.
- **Replication needs versioning on both ends.** The destination bucket is not
  managed here — pass its ARN, and its KMS key ARN when it uses SSE-KMS.
- **Object Lock is one-way.** It can only be enabled at creation and never
  removed.

## Outputs

`bucket_id`, `bucket_arn`, `bucket_domain_name`, `bucket_regional_domain_name`,
`bucket_region`, `kms_key_arn`, `kms_key_id`, `replication_role_arn`.
