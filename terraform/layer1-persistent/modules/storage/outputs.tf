output "storage_account_id" {
  description = "Azure resource ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint (e.g. for Blob CSI driver configuration)"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_ids" {
  description = "Map of container name to Azure resource ID"
  value       = { for k, v in azurerm_storage_container.this : k => v.id }
}

output "primary_access_key" {
  description = "Primary access key for the storage account (used by Blob CSI driver secret)"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}
