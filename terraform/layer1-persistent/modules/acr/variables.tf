variable "name" {
  description = "Name of the Azure Container Registry (alphanumeric, 5–50 chars)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will contain the ACR"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to the ACR"
  type        = map(string)
  default     = {}
}

variable "sku" {
  description = "ACR SKU — Basic, Standard, or Premium"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard, or Premium."
  }
}

variable "admin_enabled" {
  description = "Enable the built-in admin user (not recommended for production)"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow public network access to the registry"
  type        = bool
  default     = false
}

variable "data_endpoint_enabled" {
  description = "Enable dedicated data endpoints (Premium SKU only)"
  type        = bool
  default     = false
}

variable "anonymous_pull_enabled" {
  description = "Allow unauthenticated pulls from the registry"
  type        = bool
  default     = false
}

variable "retention_policy_days" {
  description = "Number of days to retain untagged manifests before purging (Premium SKU only)"
  type        = number
  default     = 7
}
