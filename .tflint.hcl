# TFLint configuration — https://github.com/terraform-linters/tflint
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Layer 1 is designed to survive Layer 2 teardown, but the dev environment still
# supports full destroy/recreate cycles (see .checkov.yaml: CKV_AZURE_42).
# Adding lifecycle { prevent_destroy = true } is tracked as a follow-up issue.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
