# =============================================================================
# Log Analytics Workspace
#
# ⚠️  DAILY QUOTA WARNING — READ BEFORE CHANGING daily_quota_gb
# daily_quota_gb = 5 caps ingestion at 5 GB per UTC day.
# When the cap is hit, ALL ingestion stops until the next UTC midnight:
#   • AKS control-plane logs (kube-apiserver, kube-audit, etc.) are DROPPED.
#   • OMS agent node metrics stop flowing.
#   • Microsoft Defender alerts may not appear in the workspace.
#
# This quota is intentional for the dev/experimental cost ceiling.
# If you need uninterrupted ingestion, set daily_quota_gb = -1 (unlimited)
# or raise the value — but model the cost impact first:
#   ~$2.76 / GB ingested beyond the free tier (East US, PerGB2018).
#
# Monitor quota usage:
#   az monitor log-analytics workspace show \
#     --resource-group <rg> --workspace-name <name> \
#     --query "workspaceCapping"
# =============================================================================

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 5

  internet_ingestion_enabled = true
  internet_query_enabled     = true

  tags = var.tags
}

# =============================================================================
# Azure Managed Grafana
#
# SystemAssigned identity is used for data-source authentication:
# the Monitoring Reader role below grants it read access to the Log Analytics
# workspace without any shared key or API token.
# =============================================================================

resource "azurerm_dashboard_grafana" "this" {
  name                              = "amg-${var.name_prefix}-${var.environment}"
  resource_group_name               = var.resource_group_name
  location                          = var.location
  sku                               = "Standard"
  grafana_major_version             = 11
  zone_redundancy_enabled           = false
  public_network_access_enabled     = true
  api_key_enabled                   = false
  deterministic_outbound_ip_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── Role: Grafana system identity → Log Analytics Workspace ───────────────────
# Grants Grafana's managed identity read access to query the workspace.
# This is the recommended credential-free approach for Azure Monitor data sources.

resource "azurerm_role_assignment" "grafana_law_reader" {
  scope                = azurerm_log_analytics_workspace.this.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ── Role: AAD admin group → Grafana Admin ─────────────────────────────────────
# Without this assignment no AAD user can sign in to the Grafana UI.
# The Grafana Admin built-in role grants full organisation-level access.

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.grafana_admin_group_object_id
  principal_type       = "Group"
}
