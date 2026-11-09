# Blob CSI driver and vLLM process need read access to model weights.
resource "azurerm_role_assignment" "blob_reader" {
  scope                = var.model_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# vLLM process reads secrets (e.g. HuggingFace token) via the Azure SDK.
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.keyvault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
