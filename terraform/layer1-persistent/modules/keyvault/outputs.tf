output "keyvault_id" {
  description = "Azure resource ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "keyvault_uri" {
  description = "HTTPS URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "keyvault_name" {
  description = "Name of the Key Vault (prefix + random suffix)"
  value       = azurerm_key_vault.this.name
}
