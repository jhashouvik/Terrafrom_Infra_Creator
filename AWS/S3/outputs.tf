###############################################################################
# S3 Module - Outputs
###############################################################################

output "bucket_id" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name, the one to use for VPC endpoint and CloudFront origins."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "ARN of the CMK protecting the bucket, or null when SSE-S3 is used."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "Key ID of the module-created CMK, or null when none was created."
  value       = one(aws_kms_key.this[*].key_id)
}

output "replication_role_arn" {
  description = "ARN of the replication IAM role, or null when replication is disabled."
  value       = one(aws_iam_role.replication[*].arn)
}
