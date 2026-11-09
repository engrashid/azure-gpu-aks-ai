# Remote backend — active after `terraform init -migrate-state` in bootstrap README.
# Values are hardcoded because backend blocks do not support variable references.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-qwen-persistent-dev"
    storage_account_name = "stqwentfstatedev"
    container_name       = "tfstate-layer1"
    key                  = "layer1.tfstate"
    use_azuread_auth     = true
  }
}
