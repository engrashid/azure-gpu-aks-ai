# All three private endpoints land in pe-subnet (spoke VNet).
# Each PE is paired with a DNS zone group so Azure automatically registers the
# NIC's private IP into the correct privatelink zone.

# ── ACR ────────────────────────────────────────────────────────────────────────
# Disabled: ACR downgraded to Basic SKU (no private endpoint support).
# Uncomment and upgrade ACR to Premium to re-enable private access.
#
# resource "azurerm_private_endpoint" "acr" {
#   name                = "pe-acr-${var.name_prefix}-${var.environment}"
#   resource_group_name = var.resource_group_name
#   location            = var.location
#   subnet_id           = azurerm_subnet.pe.id
#   tags                = var.tags
#
#   private_service_connection {
#     name                           = "psc-acr"
#     private_connection_resource_id = var.acr_id
#     subresource_names              = ["registry"]
#     is_manual_connection           = false
#   }
#
#   private_dns_zone_group {
#     name = "pdzg-acr"
#     private_dns_zone_ids = [
#       azurerm_private_dns_zone.zones["privatelink.azurecr.io"].id,
#     ]
#   }
# }

# ── Key Vault ──────────────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = var.keyvault_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdzg-kv"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.zones["privatelink.vaultcore.azure.net"].id,
    ]
  }
}

# ── Model weights storage ──────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "model_storage" {
  name                = "pe-model-sa-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-model-sa"
    private_connection_resource_id = var.model_storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdzg-model-sa"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.zones["privatelink.blob.core.windows.net"].id,
    ]
  }
}
