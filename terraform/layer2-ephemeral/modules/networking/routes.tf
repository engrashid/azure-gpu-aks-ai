# Route table forces all AKS egress through the firewall (UDR overrides the
# default system route).  bgp_route_propagation_enabled = false prevents
# on-premises BGP routes from overriding the UDR default route.
#
# The pe-subnet-local route keeps PE traffic (10.1.3.0/24) on the local VNet
# fabric instead of hairpinning through the firewall, which would add latency
# and consume SNAT ports for every blob/KV/ACR call from the cluster.

resource "azurerm_route_table" "aks" {
  name                          = "rt-aks-${var.name_prefix}-${var.environment}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  bgp_route_propagation_enabled = false
  tags                          = var.tags
}

resource "azurerm_route" "default_to_firewall" {
  name                   = "default-to-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.aks.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

resource "azurerm_route" "pe_subnet_local" {
  name                = "pe-subnet-local"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.aks.name
  address_prefix      = local.spoke_pe_subnet_cidr
  next_hop_type       = "VnetLocal"
}

# App Gateway probes reach AKS nodes and nginx LB via VNet-direct routing.
# Without this, response traffic from AKS nodes hairpins through the Firewall
# which has no rule for AKS→AGW subnet traffic, causing probe timeouts.
resource "azurerm_route" "appgw_subnet_local" {
  name                = "appgw-subnet-local"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.aks.name
  address_prefix      = local.spoke_appgw_subnet_cidr
  next_hop_type       = "VnetLocal"
}

resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  route_table_id = azurerm_route_table.aks.id
}
