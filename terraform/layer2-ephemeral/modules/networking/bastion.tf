# Standard SKU Bastion with tunnelling + IP connect enables native RDP/SSH from
# the portal without any additional client software.
# Set var.bastion_enabled = true to deploy; false destroys the host but keeps
# the AzureBastion subnet so the code can be re-enabled at any time.

resource "azurerm_public_ip" "bastion" {
  count               = var.bastion_enabled ? 1 : 0
  name                = "pip-bas-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = []
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count                  = var.bastion_enabled ? 1 : 0
  name                   = "bas-${var.name_prefix}-${var.environment}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  sku                    = "Standard"
  scale_units            = 2
  ip_connect_enabled     = true
  tunneling_enabled      = true
  file_copy_enabled      = true
  shareable_link_enabled = false
  tags                   = var.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
