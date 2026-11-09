output "identity_id" {
  description = "Azure resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "Client ID of the managed identity (used in workload identity federation)"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object / principal ID of the managed identity"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "tenant_id" {
  description = "Tenant ID of the managed identity"
  value       = azurerm_user_assigned_identity.this.tenant_id
}
