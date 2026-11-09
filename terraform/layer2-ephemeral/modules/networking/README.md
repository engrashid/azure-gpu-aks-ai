# modules/networking — Layer 2 Hub-Spoke Network

Manages every networking resource in the ephemeral Layer 2. Fully destroyable.
Layer 1 persistent resources (ACR, Key Vault, model storage) are wired in via
`var.acr_id`, `var.keyvault_id`, and `var.model_storage_account_id` — the
caller resolves those from `terraform_remote_state`.

---

## Architecture

```
Hub VNet (10.0.0.0/16)                Spoke VNet (10.1.0.0/16)
┌──────────────────────────┐          ┌──────────────────────────┐
│ GatewaySubnet  /27       │◄────────►│ aks-subnet         /24   │
│ AzureFirewallSubnet /26  │  Peering │ pe-subnet          /24   │
│ AzureFirewallMgmt   /26  │          └────────┬─────────────────┘
│ AzureBastionSubnet  /27  │                   │ Private Endpoints
└──────────┬───────────────┘                   │   • ACR (registry)
           │ UDR (0.0.0.0/0 → fw)              │   • Key Vault (vault)
           ▼                                   │   • Model SA (blob)
      Azure Firewall (Basic)                   │
      Application rules →                      │
      HuggingFace, PyPI, NVIDIA …              │
```

---

## Resources

| File | Resource(s) |
|---|---|
| `hub-vnet.tf` | Hub VNet + 4 subnets (incl. `AzureFirewallManagementSubnet`) |
| `spoke-vnet.tf` | Spoke VNet + `aks-subnet` + `pe-subnet` |
| `peering.tf` | Bidirectional VNet peering |
| `firewall.tf` | Firewall Policy (Basic), 2× Public IPs, Azure Firewall |
| `firewall-rules.tf` | Application rule collection group (12 allow rules) |
| `bastion.tf` | Standard Bastion + Public IP |
| `private-dns.tf` | 3 private DNS zones + 6 VNet links (hub + spoke each) |
| `private-endpoints.tf` | PE for ACR, Key Vault, model storage |
| `nsg.tf` | `aks-subnet-nsg`, `pe-subnet-nsg` + subnet associations |
| `routes.tf` | Route table + 2 routes + AKS subnet association |

---

## Azure Firewall Basic — two required subnets

Basic tier always enables forced-tunnelling mode. This requires:

| Subnet | CIDR | Purpose |
|---|---|---|
| `AzureFirewallSubnet` | `10.0.1.0/26` | Data-plane egress IP |
| `AzureFirewallManagementSubnet` | `10.0.3.0/26` | Control/management IP |

Both subnets must be at least `/26`. Neither may have an NSG attached.

---

## AzureBastionSubnet NSG (not in scope)

Azure Bastion Standard works without a dedicated NSG, but Microsoft recommends
one for defence-in-depth. If you add it, the minimum required inbound rules are:

| Priority | Source | Destination | Port | Protocol | Action |
|---|---|---|---|---|---|
| 100 | Internet | `*` | 443 | Tcp | Allow |
| 110 | GatewayManager | `*` | 443 | Tcp | Allow |
| 120 | AzureLoadBalancer | `*` | 443 | Tcp | Allow |
| 130 | VirtualNetwork | `*` | 8080, 5701 | `*` | Allow |
| 4096 | `*` | `*` | `*` | `*` | Deny |

And minimum required outbound rules:

| Priority | Destination | Port | Protocol | Action |
|---|---|---|---|---|
| 100 | VirtualNetwork | 22, 3389 | `*` | Allow |
| 110 | AzureCloud | 443 | `*` | Allow |
| 120 | Internet | 80 | `*` | Allow |

---

## Calling this module from the layer2 root

```hcl
data "terraform_remote_state" "layer1" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-qwen-persistent-dev"
    storage_account_name = "stqwentfstatedev"
    container_name       = "tfstate-layer1"
    key                  = "layer1.tfstate"
    use_azuread_auth     = true
  }
}

module "networking" {
  source = "./modules/networking"

  resource_group_name      = azurerm_resource_group.ephemeral.name
  location                 = var.location
  tags                     = local.tags
  name_prefix              = var.prefix
  environment              = var.environment

  acr_id                   = data.terraform_remote_state.layer1.outputs.acr_id
  keyvault_id              = data.terraform_remote_state.layer1.outputs.keyvault_id
  model_storage_account_id = data.terraform_remote_state.layer1.outputs.model_storage_account_id
}
```

---

## Key v4 property notes

| Old (v3) | New (v4) | Resource |
|---|---|---|
| `enforce_private_link_endpoint_network_policies = true` | `private_endpoint_network_policies = "Disabled"` | `azurerm_subnet` |
| `disable_bgp_route_propagation = true` | `bgp_route_propagation_enabled = false` | `azurerm_route_table` |
| `enable_*` prefix attributes | `*_enabled` suffix throughout | various |

---

## Firewall rule maintenance

Rules live in `firewall-rules.tf` under a single `application_rule_collection`
named `arc-workload-allow` (priority 200, action Allow). Azure Firewall's
implicit default-deny handles all unmatched traffic — no explicit deny rules
are needed or recommended.

To add a network-level rule (TCP/UDP by IP + port), add a
`network_rule_collection` block to the same
`azurerm_firewall_policy_rule_collection_group.workload` resource.
