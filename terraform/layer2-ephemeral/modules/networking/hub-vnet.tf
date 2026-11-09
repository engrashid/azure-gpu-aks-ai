# Subnet CIDRs are expressed as locals so routes.tf and peering.tf can reference
# them without duplicating magic strings.
locals {
  hub_gateway_subnet_cidr  = "10.0.0.0/27"
  hub_firewall_subnet_cidr = "10.0.1.0/26"
  hub_bastion_subnet_cidr  = "10.0.2.0/27"
  # AzureFirewallManagementSubnet is mandatory for Azure Firewall Basic tier.
  # Basic tier always uses forced-tunnelling mode, which requires this subnet
  # (minimum /26) in addition to AzureFirewallSubnet.
  hub_firewall_mgmt_subnet_cidr = "10.0.3.0/26"
}

# ── Hub VNet ───────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.hub_vnet_cidr]
  tags                = var.tags
}

# ── Hub subnets ────────────────────────────────────────────────────────────────

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_gateway_subnet_cidr]
}

# NSGs are not permitted on AzureFirewallSubnet — Azure enforces this at the API.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_firewall_subnet_cidr]
}

# Required for Azure Firewall Basic tier forced-tunnelling management traffic.
resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_firewall_mgmt_subnet_cidr]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_bastion_subnet_cidr]
}
