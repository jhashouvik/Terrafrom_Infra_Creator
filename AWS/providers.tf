###############################################################################
# Root - Provider configuration
#
# This is the ONLY place a provider is configured. Resource modules under
# ./<RESOURCE>/ inherit it, which is what lets the same module be reused
# across regions and accounts without edits.
###############################################################################

provider "aws" {
  region = var.aws_region

  # Populated by the CI pipeline through OIDC. Left null for local runs, where
  # the ambient AWS_PROFILE / SSO session is used instead.
  dynamic "assume_role" {
    for_each = var.assume_role_arn != null ? [var.assume_role_arn] : []
    content {
      role_arn     = assume_role.value
      session_name = "terraform-${var.project}"
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
