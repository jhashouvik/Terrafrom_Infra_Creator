###############################################################################
# Deployment values
#
# Terraform loads this file automatically — `terraform plan` needs no
# -var-file flag.
###############################################################################

aws_region  = "ap-south-1"
project     = "shouvik-dev"
owner       = "platform-engineering@acme.io"
cost_center = "CC-1001"

s3_buckets = {
  # Application artefacts. Customer-managed CMK, versioned, tiered to cheaper
  # storage classes as objects age.
  "app-artifacts" = {
    # Explicit physical bucket name. Set it and you get exactly this name —
    # no project prefix, no account-ID suffix. Leave it out and the name is
    # generated as "<project>-<map key>[-<account id>]" instead.
    #
    # S3 rules: 3-63 characters, lowercase letters / digits / hyphens / dots
    # only (NO uppercase), and globally unique across all of AWS.
    bucket_name = "shouvik-dev-v7"

    # AES256 = S3-managed encryption keys. Still encrypted at rest, but needs
    # no KMS permissions and costs nothing. Switch to "aws:kms" with
    # create_kms_key = true when you want a customer-managed CMK (requires
    # kms:CreateKey, CreateAlias, PutKeyPolicy, TagResource ... on the caller).
    sse_algorithm      = "AES256"
    create_kms_key     = false
    versioning_enabled = true
    force_destroy      = false

    # Resolved to the name of the "access-logs" bucket below, whether that
    # name is explicit or generated.
    logging = {
      target_bucket_key = "access-logs"
      target_prefix     = "app-artifacts/"
    }

    lifecycle_rules = [
      {
        id                                     = "tier-and-retain"
        abort_incomplete_multipart_upload_days = 7

        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
        ]

        noncurrent_version_transitions = [
          { noncurrent_days = 30, storage_class = "GLACIER" },
        ]

        noncurrent_version_expiration = {
          noncurrent_days           = 365
          newer_noncurrent_versions = 3
        }
      },
    ]

    tags = { DataClassification = "confidential" }
  }

  # Target for S3 server access logs.
  # Must be AES256: log delivery cannot write into a bucket encrypted with a
  # customer-managed CMK.
  "access-logs" = {
    bucket_name = "shouvik-dev-v7-logs"

    sse_algorithm  = "AES256"
    create_kms_key = false
    force_destroy  = false

    lifecycle_rules = [
      {
        id = "retain-logs"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER" },
        ]
        expiration = { days = 400 }
      },
    ]

    tags = { DataClassification = "internal" }
  }
}
