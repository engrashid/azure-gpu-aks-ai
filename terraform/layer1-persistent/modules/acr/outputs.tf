output "id" {
  description = "Azure resource ID of the Container Registry"
  value       = azurerm_container_registry.this.id
}

output "login_server" {
  description = "Login server FQDN of the Container Registry"
  value       = azurerm_container_registry.this.login_server
}

output "name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.this.name
}
