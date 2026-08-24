###############################################################################
# S3 Module - Provider Requirements
#
# Modules declare constraints only. Provider configuration (region, credentials,
# default_tags) is inherited from the root module in ../ so that every resource
# module stays environment agnostic and reusable.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
