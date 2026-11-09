# =============================================================================
# Layer 1 — Persistent Infrastructure
# This configuration is NEVER destroyed. Layer 2 (ephemeral) reads outputs via
# terraform_remote_state and must not own any resources defined here.
# =============================================================================

# ── Resource group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "persistent" {
  name     = "rg-${var.prefix}-persistent-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ── Terraform state storage ────────────────────────────────────────────────────
# Configuration is intentionally identical to bootstrap/main.tf so that
# `terraform plan` shows zero drift after the bootstrap import + migration.

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.prefix}tfstate${var.environment}"
  resource_group_name             = azurerm_resource_group.persistent.name
  location                        = azurerm_resource_group.persistent.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    container_delete_retention_policy {
      days = 30
    }

    delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate_layer1" {
  name                  = "tfstate-layer1"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "tfstate_layer2" {
  name                  = "tfstate-layer2"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ── Azure Container Registry ───────────────────────────────────────────────────

module "acr" {
  source = "./modules/acr"

  name                          = "acr${var.prefix}${var.environment}"
  resource_group_name           = azurerm_resource_group.persistent.name
  location                      = azurerm_resource_group.persistent.location
  tags                          = local.tags
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true
  data_endpoint_enabled         = false
  anonymous_pull_enabled        = false
  retention_policy_days         = 0
}

# ── Key Vault ──────────────────────────────────────────────────────────────────

module "keyvault" {
  source = "./modules/keyvault"

  name_prefix                   = "kv-${var.prefix}-${var.environment}"
  resource_group_name           = azurerm_resource_group.persistent.name
  location                      = azurerm_resource_group.persistent.location
  tenant_id                     = var.tenant_id
  tags                          = local.tags
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
}

# ── Model weights storage account ─────────────────────────────────────────────

module "model_storage" {
  source = "./modules/storage"

  name                          = "st${var.prefix}models${var.environment}"
  resource_group_name           = azurerm_resource_group.persistent.name
  location                      = azurerm_resource_group.persistent.location
  tags                          = local.tags
  shared_access_key_enabled     = true
  public_network_access_enabled = true

  containers = [
    { name = "model-weights", access_type = "private" },
  ]
}

# ── AAD Groups ────────────────────────────────────────────────────────────────

module "groups" {
  source = "./modules/groups"

  prefix                              = var.prefix
  additional_admin_member_object_ids  = var.additional_admin_member_object_ids
  additional_reader_member_object_ids = var.additional_reader_member_object_ids
}

# ── vLLM Managed Identity + Role Assignments ───────────────────────────────────

module "identity" {
  source = "./modules/identity"

  name                     = "mi-${var.prefix}-vllm-${var.environment}"
  resource_group_name      = azurerm_resource_group.persistent.name
  location                 = azurerm_resource_group.persistent.location
  tags                     = local.tags
  model_storage_account_id = module.model_storage.storage_account_id
  keyvault_id              = module.keyvault.keyvault_id
}
