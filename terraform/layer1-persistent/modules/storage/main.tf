locals {
  enable_blob_properties = (
    var.blob_versioning_enabled ||
    var.blob_delete_retention_days > 0 ||
    var.container_delete_retention_days > 0
  )
}

resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  account_kind                    = var.account_kind
  access_tier                     = var.access_tier
  https_traffic_only_enabled      = var.https_traffic_only_enabled
  min_tls_version                 = var.min_tls_version
  shared_access_key_enabled       = var.shared_access_key_enabled
  public_network_access_enabled   = var.public_network_access_enabled
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public

  dynamic "blob_properties" {
    for_each = local.enable_blob_properties ? [1] : []
    content {
      versioning_enabled = var.blob_versioning_enabled

      dynamic "delete_retention_policy" {
        for_each = var.blob_delete_retention_days > 0 ? [1] : []
        content {
          days = var.blob_delete_retention_days
        }
      }

      dynamic "container_delete_retention_policy" {
        for_each = var.container_delete_retention_days > 0 ? [1] : []
        content {
          days = var.container_delete_retention_days
        }
      }
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each = { for c in var.containers : c.name => c }

  name                  = each.value.name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = each.value.access_type
}
