###############################################################################
# Root - Terraform and provider versions, remote state backend
#
# Single deployment: the backend is configured inline, so `terraform init`
# needs no extra flags. Replace the bucket name below with the state bucket
# created during bootstrap (see README.md -> "Bootstrapping remote state").
#
# use_lockfile enables native S3 state locking, so no DynamoDB table is needed.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "acme-tfstate-123456789012"
    key          = "aws/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
