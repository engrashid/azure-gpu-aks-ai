# ── Resource group ─────────────────────────────────────────────────────────────

output "resource_group_name" {
  description = "Name of the ephemeral resource group"
  value       = azurerm_resource_group.main.name
}

# ── AKS ────────────────────────────────────────────────────────────────────────

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS API server"
  value       = module.aks.cluster_fqdn
}

output "aks_node_resource_group" {
  description = "Auto-generated node resource group (contains VMs, disks, NICs)"
  value       = module.aks.node_resource_group
}

# ── Networking ─────────────────────────────────────────────────────────────────

output "firewall_private_ip" {
  description = "Private IP of the Azure Firewall (UDR next-hop for aks-subnet)"
  value       = module.networking.firewall_private_ip
}

output "bastion_name" {
  description = "Name of the Azure Bastion host"
  value       = module.networking.bastion_name
}

# ── Monitoring ─────────────────────────────────────────────────────────────────

output "grafana_endpoint" {
  description = "HTTPS endpoint for the Managed Grafana UI"
  value       = module.monitoring.grafana_endpoint
}

output "law_workspace_id" {
  description = "Azure resource ID of the Log Analytics workspace"
  value       = module.monitoring.law_workspace_id
}

# ── Convenience ────────────────────────────────────────────────────────────────

output "get_credentials_command" {
  description = "Run this command to configure kubectl after apply"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --overwrite-existing"
}

# ── ArgoCD ─────────────────────────────────────────────────────────────────────

output "argocd_admin_password" {
  description = "ArgoCD initial admin password. Retrieve with: terraform output -raw argocd_admin_password"
  sensitive   = true
  value       = module.argocd.admin_password
}

output "argocd_port_forward_command" {
  description = "Command to open the ArgoCD UI on http://localhost:8080"
  value       = module.argocd.port_forward_command
}

# ── Application Gateway ─────────────────────────────────────────────────────────

output "app_gateway_public_ip" {
  description = "Public IP of the Application Gateway"
  value       = module.networking.app_gateway_public_ip
}

output "chat_ui_url" {
  description = "Public URL of the Open WebUI chat interface"
  value       = "https://chat.${var.public_domain}"
}
