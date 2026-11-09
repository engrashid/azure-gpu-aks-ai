# =============================================================================
# Layer 2 — Ephemeral Infrastructure Root
#
# Wires all modules together. Consumes Layer 1 persistent outputs via
# terraform_remote_state. This entire layer is fully destroyable; Layer 1
# resources are never touched from here.
# =============================================================================

# ── Layer 1 remote state ───────────────────────────────────────────────────────

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

# ── Ephemeral resource group ───────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-ephemeral-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ── Networking ─────────────────────────────────────────────────────────────────
# Hub-spoke VNets, Azure Firewall (Basic), Bastion, NSGs, route table,
# private DNS zones, and private endpoints for ACR / KV / model storage.

module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
  name_prefix         = var.prefix
  environment         = var.environment

  acr_id                   = data.terraform_remote_state.layer1.outputs.acr_id
  keyvault_id              = data.terraform_remote_state.layer1.outputs.keyvault_id
  model_storage_account_id = data.terraform_remote_state.layer1.outputs.model_storage_account_id

  public_domain   = var.public_domain
  bastion_enabled = false
}

# ── Monitoring ─────────────────────────────────────────────────────────────────
# Log Analytics workspace (5 GB/day cap) and Azure Managed Grafana.
# See modules/monitoring/README.md for quota impact details.

module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
  name_prefix         = var.prefix
  environment         = var.environment

  grafana_admin_group_object_id = data.terraform_remote_state.layer1.outputs.grafana_admins_group_object_id
}

# ── AKS ────────────────────────────────────────────────────────────────────────
# Public API server + authorized IP ranges (Option A).
# System, user, and GPU (T4) node pools.
# Workload Identity federation for vLLM pod.

module "aks" {
  source = "./modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
  name_prefix         = var.prefix
  environment         = var.environment

  # Networking
  aks_subnet_id = module.networking.aks_subnet_id
  spoke_vnet_id = module.networking.spoke_vnet_id

  # Observability
  law_workspace_id = module.monitoring.law_workspace_id

  # Layer 1 cross-references
  acr_id           = data.terraform_remote_state.layer1.outputs.acr_id
  vllm_identity_id = data.terraform_remote_state.layer1.outputs.vllm_identity_id

  # AAD
  tenant_id              = var.tenant_id
  admin_group_object_ids = [data.terraform_remote_state.layer1.outputs.aks_admins_group_object_id]

  # Cluster
  kubernetes_version = var.kubernetes_version
  gpu_zone           = var.gpu_zone

  # API server allowlist — includes developer laptop IPs from tfvars plus the
  # firewall public IP so nodes can reach the API server via UDR egress.
  api_server_authorized_ip_ranges = concat(
    var.api_server_authorized_ip_ranges,
    ["${module.networking.firewall_public_ip}/32"]
  )

  app_gateway_id = module.networking.app_gateway_id

  # Networking must be fully provisioned before AKS attempts to attach to the
  # subnet; monitoring must exist before OMS agent configuration is sent.
  depends_on = [module.networking, module.monitoring]
}

# ── ArgoCD ─────────────────────────────────────────────────────────────────────
# Optional GitOps control plane. Set argocd_enabled=true in tfvars after the
# AKS cluster is running. On a fresh stack, apply with argocd_enabled=false
# first (cluster creation), then re-apply with argocd_enabled=true.
#
# Existing installation: run the import script once before the first apply:
#   bash scripts/import-argocd-state.sh

module "argocd" {
  source = "./modules/argocd"

  enabled              = var.argocd_enabled
  argocd_chart_version = var.argocd_chart_version
  gitops_repo_url      = var.gitops_repo_url
  azdo_pat             = var.azdo_pat
  public_domain        = var.public_domain

  aks_admins_group_object_id = data.terraform_remote_state.layer1.outputs.aks_admins_group_object_id

  depends_on = [module.aks]
}

# ── Workload Secrets ───────────────────────────────────────────────────────────
# Kubernetes secrets that cannot be managed by GitOps (contain sensitive values
# sourced from Azure). Created automatically after AKS + ArgoCD are up.

module "workload_secrets" {
  source = "./modules/workload-secrets"

  enabled = var.argocd_enabled

  storage_account_name = data.terraform_remote_state.layer1.outputs.model_storage_account_name
  storage_account_key  = data.terraform_remote_state.layer1.outputs.model_storage_primary_access_key

  oauth2_proxy_client_id     = var.oauth2_proxy_client_id
  oauth2_proxy_app_object_id = var.oauth2_proxy_app_object_id

  depends_on = [module.argocd]
}
