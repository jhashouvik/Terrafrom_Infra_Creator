###############################################################################
# tflint - shared ruleset for the root module and every resource folder
###############################################################################

tflint {
  required_version = ">= 0.55"
}

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.42.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Enforce the <project>-<env>-<component> naming convention on modules.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Root module owns the tfvars; unused variables there are a real smell.
rule "terraform_unused_declarations" {
  enabled = true
}
