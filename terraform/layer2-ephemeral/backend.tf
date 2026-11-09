# Remote backend — points at the state container created by Layer 1 bootstrap.
# Values are hardcoded; backend blocks do not support variable references.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-qwen-persistent-dev"
    storage_account_name = "stqwentfstatedev"
    container_name       = "tfstate-layer2"
    key                  = "layer2.tfstate"
    use_azuread_auth     = true
  }
}
