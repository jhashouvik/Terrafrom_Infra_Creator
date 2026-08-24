###############################################################################
# Root - Deployment entry point
#
# This is the ONLY directory that gets `terraform init/plan/apply` run against
# it. Each sibling folder (./S3, and future ./EC2, ./VPC, ./RDS ...) is a
# reusable resource module with no provider or backend of its own.
#
# Adding a new resource type later is a two-step change:
#   1. create ./<RESOURCE>/ with main.tf + variables.tf + outputs.tf
#   2. add a module block here plus its variable and outputs
###############################################################################

module "s3" {
  source   = "./S3"
  for_each = var.s3_buckets

  bucket_name   = local.s3_bucket_names[each.key]
  force_destroy = each.value.force_destroy

  object_ownership    = each.value.object_ownership
  block_public_access = each.value.block_public_access

  versioning_enabled = each.value.versioning_enabled
  mfa_delete         = each.value.mfa_delete

  object_lock_enabled       = each.value.object_lock_enabled
  object_lock_configuration = each.value.object_lock_configuration

  sse_algorithm                   = each.value.sse_algorithm
  create_kms_key                  = each.value.create_kms_key
  kms_key_arn                     = each.value.kms_key_arn
  kms_key_deletion_window_in_days = each.value.kms_key_deletion_window_in_days
  bucket_key_enabled              = each.value.bucket_key_enabled

  attach_bucket_policy        = each.value.attach_bucket_policy
  enforce_tls                 = each.value.enforce_tls
  minimum_tls_version         = each.value.minimum_tls_version
  deny_unencrypted_uploads    = each.value.deny_unencrypted_uploads
  additional_policy_documents = each.value.additional_policy_documents

  lifecycle_rules = each.value.lifecycle_rules
  logging         = local.s3_logging[each.key]
  cors_rules      = each.value.cors_rules
  replication     = each.value.replication

  tags = merge(each.value.tags, { Component = each.key })
}

###############################################################################
# Future resource folders plug in here, e.g.
#
# module "vpc" {
#   source   = "./VPC"
#   for_each = var.vpcs
#   ...
# }
###############################################################################
