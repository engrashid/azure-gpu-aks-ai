# ── Log Analytics Workspace ────────────────────────────────────────────────────

output "law_workspace_id" {
  description = "Azure resource ID of the Log Analytics workspace (used by OMS agent, Defender, diagnostics)"
  value       = azurerm_log_analytics_workspace.this.id
}

output "law_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

output "law_customer_id" {
  description = "Log Analytics workspace GUID (shown as 'Workspace ID' in the portal)"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "law_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace (sensitive)"
  sensitive   = true
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
}

# ── Azure Managed Grafana ──────────────────────────────────────────────────────

output "grafana_id" {
  description = "Azure resource ID of the Managed Grafana instance"
  value       = azurerm_dashboard_grafana.this.id
}

output "grafana_endpoint" {
  description = "HTTPS endpoint of the Managed Grafana instance"
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "grafana_principal_id" {
  description = "Principal ID of the Grafana system-assigned managed identity"
  value       = azurerm_dashboard_grafana.this.identity[0].principal_id
}
