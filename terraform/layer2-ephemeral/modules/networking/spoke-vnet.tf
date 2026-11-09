locals {
  spoke_aks_subnet_cidr   = "10.1.1.0/24"
  spoke_appgw_subnet_cidr = "10.1.2.0/27"
  spoke_pe_subnet_cidr    = "10.1.3.0/24"
}

# ── Spoke VNet ─────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.spoke_vnet_cidr]
  tags                = var.tags
}

# ── Spoke subnets ──────────────────────────────────────────────────────────────

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_aks_subnet_cidr]
}

# Application Gateway requires its own dedicated subnet (cannot share with AKS nodes).
# /27 = 32 addresses — minimum for Standard_v2.
resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_appgw_subnet_cidr]
}

# private_endpoint_network_policies must be the string "Disabled" in azurerm v4.
# The old boolean enforce_private_link_endpoint_network_policies is removed.
resource "azurerm_subnet" "pe" {
  name                              = "pe-subnet"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [local.spoke_pe_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
}
