# ── Resource group ─────────────────────────────────────────────────────────────

output "resource_group_name" {
  description = "Name of the persistent resource group"
  value       = azurerm_resource_group.persistent.name
}

output "resource_group_id" {
  description = "Azure resource ID of the persistent resource group"
  value       = azurerm_resource_group.persistent.id
}

output "location" {
  description = "Azure region of the deployment"
  value       = azurerm_resource_group.persistent.location
}

# ── State storage ──────────────────────────────────────────────────────────────

output "state_storage_account_name" {
  description = "Name of the Terraform state storage account"
  value       = azurerm_storage_account.tfstate.name
}

# ── ACR ────────────────────────────────────────────────────────────────────────

output "acr_id" {
  description = "Azure resource ID of the Container Registry"
  value       = module.acr.id
}

output "acr_login_server" {
  description = "Login server FQDN of the Container Registry"
  value       = module.acr.login_server
}

output "acr_name" {
  description = "Name of the Container Registry"
  value       = module.acr.name
}

# ── Key Vault ──────────────────────────────────────────────────────────────────

output "keyvault_id" {
  description = "Azure resource ID of the Key Vault"
  value       = module.keyvault.keyvault_id
}

output "keyvault_uri" {
  description = "HTTPS URI of the Key Vault"
  value       = module.keyvault.keyvault_uri
}

output "keyvault_name" {
  description = "Name of the Key Vault (includes random suffix)"
  value       = module.keyvault.keyvault_name
}

# ── Model storage ──────────────────────────────────────────────────────────────

output "model_storage_account_id" {
  description = "Azure resource ID of the model weights storage account"
  value       = module.model_storage.storage_account_id
}

output "model_storage_account_name" {
  description = "Name of the model weights storage account"
  value       = module.model_storage.storage_account_name
}

output "model_storage_primary_blob_endpoint" {
  description = "Primary blob service endpoint of the model weights storage account"
  value       = module.model_storage.primary_blob_endpoint
}

output "model_storage_primary_access_key" {
  description = "Primary access key for model weights storage account (consumed by layer2 Blob CSI secret)"
  value       = module.model_storage.primary_access_key
  sensitive   = true
}

output "model_container_name" {
  description = "Name of the model-weights blob container"
  value       = "model-weights"
}

# ── AAD Groups ────────────────────────────────────────────────────────────────

output "aks_admins_group_object_id" {
  description = "Object ID of aks-admins — consumed by Layer 2 AKS admin_group_object_ids"
  value       = module.groups.aks_admins_object_id
}

output "grafana_admins_group_object_id" {
  description = "Object ID of grafana-admins — consumed by Layer 2 Grafana admin role"
  value       = module.groups.grafana_admins_object_id
}

output "vllm_readers_group_object_id" {
  description = "Object ID of vllm-readers — for k8s RBAC bindings in ArgoCD phase"
  value       = module.groups.vllm_readers_object_id
}

# ── vLLM Managed Identity ──────────────────────────────────────────────────────

output "vllm_identity_id" {
  description = "Azure resource ID of the vLLM user-assigned managed identity"
  value       = module.identity.identity_id
}

output "vllm_identity_client_id" {
  description = "Client ID of the vLLM managed identity (used in workload identity)"
  value       = module.identity.client_id
}

output "vllm_identity_principal_id" {
  description = "Object / principal ID of the vLLM managed identity"
  value       = module.identity.principal_id
}

output "vllm_identity_tenant_id" {
  description = "Tenant ID of the vLLM managed identity"
  value       = module.identity.tenant_id
}
