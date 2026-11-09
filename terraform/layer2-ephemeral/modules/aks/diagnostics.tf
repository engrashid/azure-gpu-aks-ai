# Sends AKS control-plane logs and metrics to the Log Analytics workspace.
# enabled_log replaces the deprecated log block (azurerm v4 removes retention
# policies — retention is configured on the workspace itself).
# log_analytics_destination_type defaults to "Dedicated" (resource-specific
# tables) which gives better query performance than AzureDiagnostics mode.

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${var.name_prefix}-${var.environment}"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = var.law_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "kube-audit" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }

  enabled_metric { category = "AllMetrics" }
}
