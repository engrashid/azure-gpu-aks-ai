data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Grants the AKS kubelet identity (used by every node for image pulls)
# the AcrPull role on the Layer 1 Container Registry.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# Grants the AKS control-plane managed identity Network Contributor on the
# spoke VNet so the cloud-controller-manager can provision internal load
# balancers (required for ingress-nginx internal LB, any future services).
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.spoke_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# ── AGIC addon RBAC ───────────────────────────────────────────────────────────
# The AGIC addon creates its own MSI. Grant it the permissions required to
# read/write the Application Gateway configuration.

resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = var.app_gateway_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# AGIC needs join/action on the App Gateway subnet to configure AGW networking.
resource "azurerm_role_assignment" "agic_vnet_network_contributor" {
  scope                = var.spoke_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}
