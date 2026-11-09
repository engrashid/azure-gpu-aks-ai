resource "azurerm_container_registry" "this" {
  # checkov:skip=CKV_AZURE_237:Dedicated data endpoints require Premium SKU; this stack uses Basic for cost
  # checkov:skip=CKV_AZURE_163:Defender for Containers image scanning is a subscription-level plan, not an ACR setting
  # checkov:skip=CKV_AZURE_139:Private Link for ACR requires Premium SKU; pull access is restricted by RBAC (AcrPull) and admin user is disabled
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  admin_enabled                 = var.admin_enabled
  public_network_access_enabled = var.public_network_access_enabled
  data_endpoint_enabled         = var.data_endpoint_enabled
  anonymous_pull_enabled        = var.anonymous_pull_enabled
  tags                          = var.tags

  retention_policy_in_days = var.sku == "Premium" ? var.retention_policy_days : null
}
