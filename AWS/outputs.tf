###############################################################################
# Root - Outputs
###############################################################################

output "account_id" {
  description = "AWS account the deployment landed in."
  value       = local.account_id
}

output "region" {
  description = "Region the deployment landed in."
  value       = var.aws_region
}

output "s3_buckets" {
  description = "Map of logical bucket key to its resolved attributes."
  value = {
    for key, mod in module.s3 : key => {
      id                   = mod.bucket_id
      arn                  = mod.bucket_arn
      domain_name          = mod.bucket_domain_name
      regional_domain_name = mod.bucket_regional_domain_name
      region               = mod.bucket_region
      kms_key_arn          = mod.kms_key_arn
      replication_role_arn = mod.replication_role_arn
    }
  }
}

output "s3_bucket_arns" {
  description = "Convenience map of logical bucket key to ARN, for IAM policies in other stacks."
  value       = { for key, mod in module.s3 : key => mod.bucket_arn }
}
