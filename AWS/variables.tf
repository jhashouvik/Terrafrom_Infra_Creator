###############################################################################
# Root - Input Variables
#
# Values are supplied from terraform.tfvars, which Terraform loads
# automatically. No -var-file flag is needed.
###############################################################################

#------------------------------------------------------------------------------
# Context
#------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region every resource in this root module is deployed to."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project or product identifier used as the name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}[a-z0-9]$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens, 3-22 characters."
  }
}

variable "owner" {
  description = "Team or distribution list accountable for these resources."
  type        = string
}

variable "cost_center" {
  description = "Cost centre / chargeback code applied to every resource."
  type        = string
  default     = "unassigned"
}

variable "assume_role_arn" {
  description = "IAM role the provider assumes. Normally null: the pipeline already assumes a role via OIDC before Terraform starts."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Extra tags merged into the default_tags of every resource."
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Naming
#------------------------------------------------------------------------------

variable "append_account_id_to_bucket_names" {
  description = "Append the account ID to generated bucket names. S3 names are globally unique, so this avoids collisions between accounts."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# S3
#
# Map key = logical bucket name. It becomes part of the physical bucket name
# and, more importantly, is the Terraform state address. Renaming a key
# destroys and recreates the bucket, so treat keys as immutable.
#------------------------------------------------------------------------------

variable "s3_buckets" {
  description = "Buckets to manage. Each entry is passed straight to the ./S3 module."
  type = map(object({
    # Explicit physical bucket name. When set it is used verbatim: no project
    # prefix and no account-ID suffix. When omitted the name is generated as
    # "<project>-<map key>[-<account id>]" (see locals.tf).
    bucket_name   = optional(string)
    force_destroy = optional(bool, false)
    tags          = optional(map(string), {})

    object_ownership    = optional(string, "BucketOwnerEnforced")
    block_public_access = optional(bool, true)

    versioning_enabled = optional(bool, true)
    mfa_delete         = optional(bool, false)

    object_lock_enabled = optional(bool, false)
    object_lock_configuration = optional(object({
      mode  = string
      days  = optional(number)
      years = optional(number)
    }))

    sse_algorithm                   = optional(string, "aws:kms")
    create_kms_key                  = optional(bool, true)
    kms_key_arn                     = optional(string)
    kms_key_deletion_window_in_days = optional(number, 30)
    bucket_key_enabled              = optional(bool, true)

    attach_bucket_policy        = optional(bool, true)
    enforce_tls                 = optional(bool, true)
    minimum_tls_version         = optional(string, "1.2")
    deny_unencrypted_uploads    = optional(bool, false)
    additional_policy_documents = optional(list(string), [])

    lifecycle_rules = optional(list(object({
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
    })), [])

    # Set exactly one of target_bucket (an external bucket name) or
    # target_bucket_key (another key in this same map, whose generated name is
    # resolved for you).
    logging = optional(object({
      target_bucket     = optional(string)
      target_bucket_key = optional(string)
      target_prefix     = optional(string, "s3-access-logs/")
    }))

    cors_rules = optional(list(object({
      id              = optional(string)
      allowed_methods = list(string)
      allowed_origins = list(string)
      allowed_headers = optional(list(string))
      expose_headers  = optional(list(string))
      max_age_seconds = optional(number)
    })), [])

    replication = optional(object({
      destination_bucket_arn    = string
      destination_storage_class = optional(string, "STANDARD_IA")
      destination_account_id    = optional(string)
      destination_kms_key_arn   = optional(string)
      replica_modifications     = optional(bool, true)
      delete_marker_replication = optional(bool, true)
      prefix                    = optional(string)
      rule_id                   = optional(string, "primary-replication-rule")
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, cfg in var.s3_buckets :
      cfg.logging == null ? true : ((cfg.logging.target_bucket == null) != (cfg.logging.target_bucket_key == null))
    ])
    error_message = "Each logging block must set exactly one of target_bucket or target_bucket_key."
  }

  validation {
    condition = alltrue([
      for key, cfg in var.s3_buckets :
      (cfg.logging == null || cfg.logging.target_bucket_key == null)
      ? true
      : contains(keys(var.s3_buckets), cfg.logging.target_bucket_key)
    ])
    error_message = "logging.target_bucket_key must name another key in s3_buckets."
  }

  # S3 rejects uppercase in bucket names. Catching it here names the offending
  # map key, instead of failing deep inside the module or at apply time.
  validation {
    condition = alltrue([
      for key, cfg in var.s3_buckets :
      cfg.bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", cfg.bucket_name))
    ])
    error_message = "Every bucket_name must be 3-63 chars of lowercase letters, digits, hyphens or dots, starting and ending with a letter or digit. Uppercase is not allowed by S3."
  }
}
