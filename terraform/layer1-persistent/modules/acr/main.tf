resource "azurerm_container_registry" "this" {
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
