# =============================================================================
# Application Gateway — Standard_v2
#
# Deployed in appgw-subnet (10.1.2.0/27) of the spoke VNet, same VNet as AKS.
# AGIC (enabled as an AKS addon) manages all backend pools, HTTP settings,
# listeners, and routing rules — the skeleton config here is the minimum
# required to create the resource; AGIC overwrites it on first sync.
#
# Ingress flow:
#   Internet → AGW public IP (port 80/443) → appgw-subnet → AKS nodes (aks-subnet)
#   (No Azure Firewall hop — AGW has its own public IP; Firewall is egress-only.)
# =============================================================================

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  # checkov:skip=CKV_AZURE_120:WAF mode is optional for dev; enable WAF_v2 SKU for production
  # checkov:skip=CKV_AZURE_217:SSL policy override applied below (TLSv1_2 minimum)
  # checkov:skip=CKV_AZURE_218:Predefined AppGwSslPolicy20220101 enforces TLSv1_2 minimum; checkov only recognises Custom/CustomV2 policies
  name                = "agw-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Fixed capacity=1: cheapest billing unit for Standard_v2.
  # Upgrade to autoscale_configuration when traffic warrants it.
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  # Single zone — matches the GPU node pool zone and avoids cross-zone charges.
  zones = ["1"]

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # ── Skeleton backend / listener / rule ────────────────────────────────────────
  # AGIC replaces these with real entries derived from Ingress objects.

  backend_address_pool {
    name = "default-pool"
  }

  backend_http_settings {
    name                  = "default-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "default-listener"
    frontend_ip_configuration_name = "appgw-frontend-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "default-rule"
    rule_type                  = "Basic"
    priority                   = 1
    http_listener_name         = "default-listener"
    backend_address_pool_name  = "default-pool"
    backend_http_settings_name = "default-http-settings"
  }

  # ── TLS policy ────────────────────────────────────────────────────────────────
  # AGIC adds SSL certificates and HTTPS listeners when an Ingress specifies TLS.

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  # AGIC manages backend pool membership and routing rules; ignoring these
  # prevents Terraform from fighting AGIC over the AGW configuration.
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      ssl_certificate,
      tags["managed-by-k8s-ingress"],
    ]
  }
}
