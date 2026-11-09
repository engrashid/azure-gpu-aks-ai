# Random suffix prevents name clashes when a soft-deleted vault from a previous
# destroy cycle still holds the name within the retention window.
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_key_vault" "this" {
  name                          = "${var.name_prefix}-${random_string.suffix.result}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = var.sku_name
  rbac_authorization_enabled    = var.enable_rbac_authorization
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    default_action = var.network_acls_default_action
    bypass         = var.network_acls_bypass
  }

  tags = var.tags
}
