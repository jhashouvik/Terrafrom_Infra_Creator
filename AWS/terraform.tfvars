###############################################################################
# Deployment values
#
# Terraform loads this file automatically — `terraform plan` needs no
# -var-file flag.
###############################################################################

aws_region  = "ap-south-1"
project     = "acme"
owner       = "platform-engineering@acme.io"
cost_center = "CC-1001"

s3_buckets = {
  # Application artefacts. Customer-managed CMK, versioned, tiered to cheaper
  # storage classes as objects age.
  "app-artifacts" = {
    sse_algorithm      = "aws:kms"
    create_kms_key     = true
    versioning_enabled = true
    force_destroy      = false

    # Resolved to the generated name of the "access-logs" bucket below.
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
