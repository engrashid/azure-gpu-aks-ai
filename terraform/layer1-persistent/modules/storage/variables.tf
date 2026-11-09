variable "name" {
  description = "Storage account name (3–24 chars, lowercase alphanumeric only)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the storage account"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to the storage account"
  type        = map(string)
  default     = {}
}

variable "account_tier" {
  description = "Storage account tier — Standard or Premium"
  type        = string
  default     = "Standard"
}

variable "account_replication_type" {
  description = "Replication strategy — LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS"
  type        = string
  default     = "LRS"
}

variable "account_kind" {
  description = "Storage account kind — BlobStorage, BlockBlobStorage, FileStorage, Storage, or StorageV2"
  type        = string
  default     = "StorageV2"
}

variable "access_tier" {
  description = "Default access tier for blob storage — Hot or Cool"
  type        = string
  default     = "Hot"
}

variable "https_traffic_only_enabled" {
  description = "Require HTTPS for all requests"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version — TLS1_0, TLS1_1, or TLS1_2"
  type        = string
  default     = "TLS1_2"
}

variable "shared_access_key_enabled" {
  description = "Allow Shared Key (storage account key) authentication"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Allow access from public networks"
  type        = bool
  default     = true
}

variable "allow_nested_items_to_be_public" {
  description = "Allow blobs and containers to have public access levels"
  type        = bool
  default     = false
}

variable "blob_versioning_enabled" {
  description = "Enable blob versioning"
  type        = bool
  default     = false
}


variable "blob_delete_retention_days" {
  description = "Soft-delete retention for blobs in days (0 = disabled)"
  type        = number
  default     = 0

  validation {
    condition     = var.blob_delete_retention_days >= 0 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 0 and 365."
  }
}

variable "container_delete_retention_days" {
  description = "Soft-delete retention for containers in days (0 = disabled)"
  type        = number
  default     = 0

  validation {
    condition     = var.container_delete_retention_days >= 0 && var.container_delete_retention_days <= 365
    error_message = "container_delete_retention_days must be between 0 and 365."
  }
}

variable "containers" {
  description = "List of blob containers to create inside the storage account"
  type = list(object({
    name        = string
    access_type = string
  }))
  default = []
}
