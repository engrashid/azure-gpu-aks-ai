locals {
  tags = {
    environment = var.environment
    layer       = "persistent"
    managed_by  = "terraform"
    project     = "${var.prefix}-experimental"
    cost_center = var.cost_center
  }
}

# ── Resource group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "persistent" {
  name     = "rg-${var.prefix}-persistent-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ── Terraform state storage account ───────────────────────────────────────────
# Identical configuration to what layer1-persistent/main.tf will manage after
# state migration, so terraform plan shows zero drift after import.

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.prefix}tfstate${var.environment}"
  resource_group_name             = azurerm_resource_group.persistent.name
  location                        = azurerm_resource_group.persistent.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    container_delete_retention_policy {
      days = 30
    }

    delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

# ── State containers ───────────────────────────────────────────────────────────

resource "azurerm_storage_container" "tfstate_layer1" {
  name                  = "tfstate-layer1"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "tfstate_layer2" {
  name                  = "tfstate-layer2"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
