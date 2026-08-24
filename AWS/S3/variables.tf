###############################################################################
# S3 Module - Input Variables
###############################################################################

#------------------------------------------------------------------------------
# Identity
#------------------------------------------------------------------------------

variable "bucket_name" {
  description = "Globally unique name of the S3 bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase alphanumeric / dot / hyphen, and start and end with an alphanumeric character."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. Keep false for anything production-like."
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Ownership and public access
#------------------------------------------------------------------------------

variable "object_ownership" {
  description = "Object ownership setting. BucketOwnerEnforced disables ACLs entirely (recommended)."
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be BucketOwnerEnforced, BucketOwnerPreferred or ObjectWriter."
  }
}

variable "block_public_access" {
  description = "Organisation guardrail: block all four forms of public access. Only disable with a documented exception."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Versioning and Object Lock
#------------------------------------------------------------------------------

variable "versioning_enabled" {
  description = "Enable object versioning. Required for replication and for noncurrent-version lifecycle rules."
  type        = bool
  default     = true
}

variable "mfa_delete" {
  description = "Enable MFA delete. Can only be toggled by the bucket owner root user with an MFA device present."
  type        = bool
  default     = false
}

variable "object_lock_enabled" {
  description = "Enable S3 Object Lock (WORM). Must be set at bucket creation time and cannot be turned off later."
  type        = bool
  default     = false
}

variable "object_lock_configuration" {
  description = "Default Object Lock retention. Only used when object_lock_enabled is true."
  type = object({
    mode  = string           # GOVERNANCE or COMPLIANCE
    days  = optional(number) # mutually exclusive with years
    years = optional(number)
  })
  default = null

  validation {
    condition = var.object_lock_configuration == null ? true : (
      contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_configuration.mode) &&
      ((var.object_lock_configuration.days == null) != (var.object_lock_configuration.years == null))
    )
    error_message = "object_lock_configuration.mode must be GOVERNANCE or COMPLIANCE, and exactly one of days or years must be set."
  }
}

#------------------------------------------------------------------------------
# Encryption
#------------------------------------------------------------------------------

variable "sse_algorithm" {
  description = "Server side encryption algorithm: AES256 (SSE-S3) or aws:kms (SSE-KMS)."
  type        = string
  default     = "aws:kms"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either AES256 or aws:kms."
  }
}

variable "create_kms_key" {
  description = "Create a dedicated, auto-rotated CMK for this bucket. Ignored unless sse_algorithm is aws:kms."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing CMK to use. Takes precedence over create_kms_key when set."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period before a module-created CMK is deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}

variable "bucket_key_enabled" {
  description = "Use an S3 Bucket Key to reduce KMS request cost. Recommended whenever SSE-KMS is used."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Bucket policy
#------------------------------------------------------------------------------

variable "attach_bucket_policy" {
  description = "Attach the module-managed bucket policy (TLS guardrails plus any additional documents)."
  type        = bool
  default     = true
}

variable "enforce_tls" {
  description = "Deny every request that does not travel over TLS."
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Deny requests below this TLS version. Set to null to skip the check."
  type        = string
  default     = "1.2"
}

variable "deny_unencrypted_uploads" {
  description = "Deny PutObject calls whose x-amz-server-side-encryption header contradicts sse_algorithm. Requests that omit the header are still allowed so default bucket encryption can apply."
  type        = bool
  default     = false
}

variable "additional_policy_documents" {
  description = "Extra IAM policy JSON documents merged into the bucket policy, e.g. cross-account read access."
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Lifecycle
#------------------------------------------------------------------------------

variable "lifecycle_rules" {
  description = "Lifecycle rules. An empty list disables the lifecycle configuration entirely."
  type = list(object({
    id                                     = string
    enabled                                = optional(bool, true)
    prefix                                 = optional(string)
    tags                                   = optional(map(string))
    abort_incomplete_multipart_upload_days = optional(number)

    expiration = optional(object({
      days                         = optional(number)
      date                         = optional(string)
      expired_object_delete_marker = optional(bool)
    }))

    noncurrent_version_expiration = optional(object({
      noncurrent_days           = number
      newer_noncurrent_versions = optional(number)
    }))

    transitions = optional(list(object({
      days          = optional(number)
      date          = optional(string)
      storage_class = string
    })), [])

    noncurrent_version_transitions = optional(list(object({
      noncurrent_days           = number
      storage_class             = string
      newer_noncurrent_versions = optional(number)
    })), [])
  }))
  default = []
}

#------------------------------------------------------------------------------
# Server access logging
#------------------------------------------------------------------------------

variable "logging" {
  description = "Ship S3 server access logs to another bucket. Null disables logging."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "s3-access-logs/")
  })
  default = null
}

#------------------------------------------------------------------------------
# CORS
#------------------------------------------------------------------------------

variable "cors_rules" {
  description = "CORS rules for the bucket."
  type = list(object({
    id              = optional(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}

#------------------------------------------------------------------------------
# Cross-region replication
#------------------------------------------------------------------------------

variable "replication" {
  description = "Cross-region or cross-account replication. Requires versioning_enabled. The module creates the replication IAM role. destination_kms_key_arn is required when the destination bucket uses SSE-KMS."
  type = object({
    destination_bucket_arn    = string
    destination_storage_class = optional(string, "STANDARD_IA")
    destination_account_id    = optional(string)
    destination_kms_key_arn   = optional(string)
    replica_modifications     = optional(bool, true)
    delete_marker_replication = optional(bool, true)
    prefix                    = optional(string)
    rule_id                   = optional(string, "primary-replication-rule")
  })
  default = null
}
