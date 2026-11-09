# ── Hub VNet ───────────────────────────────────────────────────────────────────

output "hub_vnet_id" {
  description = "Azure resource ID of the Hub VNet"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Name of the Hub VNet"
  value       = azurerm_virtual_network.hub.name
}

# ── Spoke VNet ─────────────────────────────────────────────────────────────────

output "spoke_vnet_id" {
  description = "Azure resource ID of the Spoke VNet"
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_name" {
  description = "Name of the Spoke VNet"
  value       = azurerm_virtual_network.spoke.name
}

# ── Subnets ────────────────────────────────────────────────────────────────────

output "aks_subnet_id" {
  description = "Azure resource ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "pe_subnet_id" {
  description = "Azure resource ID of the private-endpoint subnet"
  value       = azurerm_subnet.pe.id
}

# ── Firewall ───────────────────────────────────────────────────────────────────

output "firewall_id" {
  description = "Azure resource ID of the Azure Firewall"
  value       = azurerm_firewall.this.id
}

output "firewall_private_ip" {
  description = "Private IP address of the firewall (used as UDR next-hop)"
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP of the firewall data interface — must be in AKS api_server_authorized_ip_ranges so nodes can reach the API server via UDR"
  value       = azurerm_public_ip.firewall_data.ip_address
}

output "firewall_policy_id" {
  description = "Azure resource ID of the Firewall Policy"
  value       = azurerm_firewall_policy.this.id
}

# ── Bastion ────────────────────────────────────────────────────────────────────

output "bastion_id" {
  description = "Azure resource ID of the Bastion host (empty string when disabled)"
  value       = var.bastion_enabled ? azurerm_bastion_host.this[0].id : ""
}

output "bastion_name" {
  description = "Name of the Bastion host (empty string when disabled)"
  value       = var.bastion_enabled ? azurerm_bastion_host.this[0].name : ""
}

# ── Route Table ────────────────────────────────────────────────────────────────

output "route_table_id" {
  description = "Azure resource ID of the AKS subnet route table"
  value       = azurerm_route_table.aks.id
}

# ── Private DNS ────────────────────────────────────────────────────────────────

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name to Azure resource ID"
  value       = { for k, v in azurerm_private_dns_zone.zones : k => v.id }
}

# ── Application Gateway ─────────────────────────────────────────────────────────

output "app_gateway_id" {
  description = "Azure resource ID of the Application Gateway (passed to AKS AGIC addon)"
  value       = azurerm_application_gateway.this.id
}

output "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway — create a DNS A record pointing your chat hostname here"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_subnet_id" {
  description = "Azure resource ID of the Application Gateway subnet"
  value       = azurerm_subnet.appgw.id
}
