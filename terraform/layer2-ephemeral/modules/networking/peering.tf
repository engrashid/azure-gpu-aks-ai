# Hub → Spoke: forwards traffic and advertises its gateway routes into the spoke.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
  use_remote_gateways       = false
}

# Spoke → Hub: uses hub's gateway for on-premises connectivity.
# use_remote_gateways=false keeps this simple for dev; set true when a VPN/ER
# gateway is deployed in GatewaySubnet.
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false

  depends_on = [azurerm_virtual_network_peering.hub_to_spoke]
}
