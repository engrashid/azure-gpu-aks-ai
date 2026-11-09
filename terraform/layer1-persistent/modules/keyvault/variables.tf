variable "name_prefix" {
  description = "Prefix for the Key Vault name; a 4-char random suffix is appended to avoid soft-delete name clashes"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the Key Vault"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the Key Vault"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to the Key Vault"
  type        = map(string)
  default     = {}
}

variable "sku_name" {
  description = "SKU for the Key Vault — standard or premium"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "enable_rbac_authorization" {
  description = "Use Azure RBAC for data-plane authorisation instead of access policies"
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "Prevent purging the vault and its objects during the retention period"
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Number of days soft-deleted objects are retained (7–90)"
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "Allow access to the vault from public networks"
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "Default network ACL action when no rule matches — Allow or Deny"
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "network_acls_default_action must be Allow or Deny."
  }
}

variable "network_acls_bypass" {
  description = "Traffic that bypasses network rules — AzureServices or None"
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls_bypass)
    error_message = "network_acls_bypass must be AzureServices or None."
  }
}
