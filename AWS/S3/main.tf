###############################################################################
# S3 Module - Bucket, encryption, guardrails, lifecycle, replication
#
# Design notes
#  * One module instance manages exactly ONE bucket. Fan-out (many buckets)
#    is the root module's job via for_each, which keeps addresses stable and
#    blast radius small.
#  * Every sub-resource is a separate aws_s3_bucket_* resource, never the
#    deprecated inline blocks on aws_s3_bucket.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # SSE-KMS is active only when the algorithm asks for it.
  use_kms = var.sse_algorithm == "aws:kms"

  # Precedence: explicit ARN > module-created key > none.
  create_kms_key = local.use_kms && var.create_kms_key && var.kms_key_arn == null
  kms_key_arn    = local.use_kms ? try(coalesce(var.kms_key_arn, one(aws_kms_key.this[*].arn)), null) : null

  enable_replication = var.replication != null

  tags = var.tags
}

###############################################################################
# Bucket
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket              = var.bucket_name
  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock_enabled

  tags = merge(local.tags, { Name = var.bucket_name })

  lifecycle {
    precondition {
      condition     = local.enable_replication ? var.versioning_enabled : true
      error_message = "Replication requires versioning_enabled = true on the source bucket."
    }

    precondition {
      condition     = var.object_lock_enabled ? var.versioning_enabled : true
      error_message = "Object Lock requires versioning_enabled = true."
    }
  }
}

###############################################################################
# Ownership controls and public access block
#
# The public access block is created first so the bucket is never briefly
# reachable while a policy is being attached.
###############################################################################

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

###############################################################################
# Versioning
###############################################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status     = var.versioning_enabled ? "Enabled" : "Suspended"
    mfa_delete = var.mfa_delete ? "Enabled" : "Disabled"
  }
}

###############################################################################
# Object Lock
###############################################################################

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock_enabled && var.object_lock_configuration != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode  = var.object_lock_configuration.mode
      days  = var.object_lock_configuration.days
      years = var.object_lock_configuration.years
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

###############################################################################
# Encryption
###############################################################################

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "CMK for S3 bucket ${var.bucket_name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = merge(local.tags, { Name = "${var.bucket_name}-cmk" })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${var.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  # Without this the key becomes unmanageable.
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Scope S3 service usage to this account only.
  statement {
    sid    = "AllowS3ServiceUse"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = local.kms_key_arn
    }

    bucket_key_enabled = local.use_kms ? var.bucket_key_enabled : null
  }
}

###############################################################################
# Bucket policy
###############################################################################

data "aws_iam_policy_document" "bucket" {
  count = var.attach_bucket_policy ? 1 : 0

  source_policy_documents = var.additional_policy_documents

  dynamic "statement" {
    for_each = var.enforce_tls ? [1] : []
    content {
      sid    = "DenyInsecureTransport"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions = ["s3:*"]
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.minimum_tls_version != null ? [var.minimum_tls_version] : []
    content {
      sid    = "DenyOutdatedTLS"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions = ["s3:*"]
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      condition {
        test     = "NumericLessThan"
        variable = "s3:TlsVersion"
        values   = [statement.value]
      }
    }
  }

  # Only fires when the caller explicitly asks for the wrong algorithm.
  # A missing header falls through to default bucket encryption.
  dynamic "statement" {
    for_each = var.deny_unencrypted_uploads ? [1] : []
    content {
      sid       = "DenyIncorrectEncryptionHeader"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption"
        values   = [var.sse_algorithm]
      }
      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["false"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = var.attach_bucket_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket[0].json

  # A policy must never land before public access is locked down.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

###############################################################################
# Lifecycle
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        # A tag filter must be expressed through an `and` block; a bare
        # prefix can stay on the filter itself.
        prefix = rule.value.tags == null ? coalesce(rule.value.prefix, "") : null

        dynamic "and" {
          for_each = rule.value.tags != null ? [1] : []
          content {
            prefix = rule.value.prefix
            tags   = rule.value.tags
          }
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []
        content {
          days                         = expiration.value.days
          date                         = expiration.value.date
          expired_object_delete_marker = expiration.value.expired_object_delete_marker
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          date          = transition.value.date
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration != null ? [rule.value.noncurrent_version_expiration] : []
        content {
          noncurrent_days           = noncurrent_version_expiration.value.noncurrent_days
          newer_noncurrent_versions = noncurrent_version_expiration.value.newer_noncurrent_versions
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions
        content {
          noncurrent_days           = noncurrent_version_transition.value.noncurrent_days
          newer_noncurrent_versions = noncurrent_version_transition.value.newer_noncurrent_versions
          storage_class             = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

###############################################################################
# Server access logging
###############################################################################

resource "aws_s3_bucket_logging" "this" {
  count = var.logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging.target_bucket
  target_prefix = var.logging.target_prefix
}

###############################################################################
# CORS
###############################################################################

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      id              = cors_rule.value.id
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

###############################################################################
# Cross-region replication
###############################################################################

data "aws_iam_policy_document" "replication_assume_role" {
  count = local.enable_replication ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = local.enable_replication ? 1 : 0

  name               = "${var.bucket_name}-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role[0].json
  tags               = local.tags
}

data "aws_iam_policy_document" "replication" {
  count = local.enable_replication ? 1 : 0

  statement {
    sid    = "ReadSourceBucket"
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadSourceObjects"
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid    = "WriteDestinationObjects"
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner",
    ]
    resources = ["${var.replication.destination_bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = local.kms_key_arn != null ? [local.kms_key_arn] : []
    content {
      sid       = "DecryptSourceObjects"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }

  dynamic "statement" {
    for_each = var.replication.destination_kms_key_arn != null ? [var.replication.destination_kms_key_arn] : []
    content {
      sid       = "EncryptDestinationObjects"
      effect    = "Allow"
      actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "replication" {
  count = local.enable_replication ? 1 : 0

  name   = "${var.bucket_name}-replication"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = local.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.this.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = var.replication.rule_id
    status = "Enabled"

    filter {
      prefix = coalesce(var.replication.prefix, "")
    }

    delete_marker_replication {
      status = var.replication.delete_marker_replication ? "Enabled" : "Disabled"
    }

    source_selection_criteria {
      replica_modifications {
        status = var.replication.replica_modifications ? "Enabled" : "Disabled"
      }

      dynamic "sse_kms_encrypted_objects" {
        for_each = local.kms_key_arn != null ? [1] : []
        content {
          status = "Enabled"
        }
      }
    }

    destination {
      bucket        = var.replication.destination_bucket_arn
      storage_class = var.replication.destination_storage_class
      account       = var.replication.destination_account_id

      dynamic "encryption_configuration" {
        for_each = var.replication.destination_kms_key_arn != null ? [var.replication.destination_kms_key_arn] : []
        content {
          replica_kms_key_id = encryption_configuration.value
        }
      }

      dynamic "access_control_translation" {
        for_each = var.replication.destination_account_id != null ? [1] : []
        content {
          owner = "Destination"
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
