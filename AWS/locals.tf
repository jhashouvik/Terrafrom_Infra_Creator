###############################################################################
# Root - Shared naming and tagging
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Standard prefix for every physical resource name.
  name_prefix = var.project

  # Applied to every resource through the provider's default_tags.
  common_tags = merge(
    {
      Project    = var.project
      Owner      = var.owner
      CostCenter = var.cost_center
      ManagedBy  = "Terraform"
      Repository = "Terrafrom_Infra_Creator/AWS"
    },
    var.additional_tags,
  )

  # Resolve each logical bucket to its physical name once, so the module call,
  # the logging cross-references and the outputs all agree.
  s3_bucket_names = {
    for key, cfg in var.s3_buckets :
    key => coalesce(
      cfg.bucket_name,
      var.append_account_id_to_bucket_names
      ? "${local.name_prefix}-${key}-${local.account_id}"
      : "${local.name_prefix}-${key}"
    )
  }

  # A logging target given as target_bucket_key is turned into the real bucket
  # name here, so tfvars never has to hard-code a generated name.
  s3_logging = {
    for key, cfg in var.s3_buckets :
    key => cfg.logging == null ? null : {
      target_bucket = (
        cfg.logging.target_bucket != null
        ? cfg.logging.target_bucket
        : local.s3_bucket_names[cfg.logging.target_bucket_key]
      )
      target_prefix = cfg.logging.target_prefix
    }
  }
}
