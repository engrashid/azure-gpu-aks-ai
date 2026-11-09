output "resource_group_name" {
  description = "Name of the persistent resource group"
  value       = azurerm_resource_group.persistent.name
}

output "resource_group_id" {
  description = "Azure resource ID of the persistent resource group"
  value       = azurerm_resource_group.persistent.id
}

output "state_storage_account_name" {
  description = "Name of the Terraform state storage account — plug into layer1 backend config"
  value       = azurerm_storage_account.tfstate.name
}

output "state_storage_account_id" {
  description = "Azure resource ID of the Terraform state storage account"
  value       = azurerm_storage_account.tfstate.id
}

output "tfstate_layer1_container_id" {
  description = "Azure resource ID of the tfstate-layer1 container"
  value       = azurerm_storage_container.tfstate_layer1.id
}

output "tfstate_layer2_container_id" {
  description = "Azure resource ID of the tfstate-layer2 container"
  value       = azurerm_storage_container.tfstate_layer2.id
}
