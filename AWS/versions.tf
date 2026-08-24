###############################################################################
# Root - Terraform and provider versions, remote state backend
#
# The backend is a PARTIAL configuration: bucket and region are supplied at
# init time, because the state bucket name embeds the AWS account id and is
# therefore not known until the pipeline authenticates.
#
#   terraform init -backend-config="bucket=<your-state-bucket>" -backend-config="region=ap-south-1"
#
# CI resolves and passes both automatically - see the "Ensure state bucket
# exists" step in .github/workflows/terraform-reusable.yml.
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
    # bucket and region are injected via -backend-config at init time.
    key          = "aws/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
