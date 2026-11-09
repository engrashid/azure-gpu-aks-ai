# =============================================================================
# Azure Firewall — Basic tier
#
# Basic tier enforces forced-tunnelling mode, which means:
#   • ip_configuration        — data-plane traffic, uses AzureFirewallSubnet
#   • management_ip_configuration — control/management traffic,
#                               uses AzureFirewallManagementSubnet
# Both public IPs must be Standard SKU / Static allocation.
# The attached firewall policy must also be Basic SKU (tiers cannot be mixed).
# =============================================================================

# ── Public IPs ─────────────────────────────────────────────────────────────────

resource "azurerm_public_ip" "firewall_data" {
  name                = "pip-afw-data-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = []
  tags                = var.tags
}

resource "azurerm_public_ip" "firewall_mgmt" {
  name                = "pip-afw-mgmt-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = []
  tags                = var.tags
}

# ── Firewall Policy (Basic) ────────────────────────────────────────────────────

resource "azurerm_firewall_policy" "this" {
  name                = "afwp-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  tags                = var.tags
}

# ── Azure Firewall ─────────────────────────────────────────────────────────────

resource "azurerm_firewall" "this" {
  name                = "afw-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.tags

  # Data-plane traffic — egress from spoke workloads hits this IP/subnet.
  ip_configuration {
    name                 = "data-configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall_data.id
  }

  # Management-plane traffic — required by Basic tier forced-tunnelling mode.
  management_ip_configuration {
    name                 = "mgmt-configuration"
    subnet_id            = azurerm_subnet.firewall_management.id
    public_ip_address_id = azurerm_public_ip.firewall_mgmt.id
  }
}
