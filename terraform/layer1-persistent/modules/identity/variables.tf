variable "name" {
  description = "Name of the user-assigned managed identity"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the managed identity"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to the managed identity"
  type        = map(string)
  default     = {}
}

variable "model_storage_account_id" {
  description = "Resource ID of the model weights storage account (scope for Storage Blob Data Reader)"
  type        = string
}

variable "keyvault_id" {
  description = "Resource ID of the Key Vault (scope for Key Vault Secrets User)"
  type        = string
}
