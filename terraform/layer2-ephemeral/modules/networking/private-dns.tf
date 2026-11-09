locals {
  dns_zone_names = toset([
    # "privatelink.azurecr.io",  # re-enable when ACR upgraded to Premium
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
  ])

  # Cross-product: 3 zones × 2 VNets = 6 link resources.
  dns_vnet_links = {
    for pair in setproduct(tolist(local.dns_zone_names), ["hub", "spoke"]) :
    "${pair[0]}-${pair[1]}" => {
      zone_name  = pair[0]
      vnet_label = pair[1]
      vnet_id    = pair[1] == "hub" ? azurerm_virtual_network.hub.id : azurerm_virtual_network.spoke.id
    }
  }
}

# ── Private DNS Zones ──────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.dns_zone_names
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ── VNet links ─────────────────────────────────────────────────────────────────
# Registration is disabled on all links — these zones resolve PE records only.
# Auto-registration would pollute DNS with VM hostnames.

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each = local.dns_vnet_links

  name                  = "link-${each.value.vnet_label}-${replace(each.value.zone_name, ".", "-")}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.value.zone_name].name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}
