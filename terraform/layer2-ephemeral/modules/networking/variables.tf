variable "resource_group_name" {
  description = "Name of the resource group that owns all networking resources"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "tags" {
  description = "Map of tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Short prefix used in every resource name"
  type        = string
  default     = "qwen"
}

variable "environment" {
  description = "Environment suffix used in every resource name"
  type        = string
  default     = "dev"
}

# ── Address spaces ──────────────────────────────────────────────────────────────

variable "hub_vnet_cidr" {
  description = "Address space for the Hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "spoke_vnet_cidr" {
  description = "Address space for the Spoke VNet"
  type        = string
  default     = "10.1.0.0/16"
}

# ── Layer 1 resource IDs passed in from terraform_remote_state ─────────────────

# Reserved for the ACR private endpoint in private-endpoints.tf, which is
# commented out because Private Link requires the ACR Premium SKU.
# tflint-ignore: terraform_unused_declarations
variable "acr_id" {
  description = "Resource ID of the Layer 1 Azure Container Registry"
  type        = string
}

variable "keyvault_id" {
  description = "Resource ID of the Layer 1 Key Vault"
  type        = string
}

variable "model_storage_account_id" {
  description = "Resource ID of the Layer 1 model weights storage account"
  type        = string
}

variable "bastion_enabled" {
  description = "Deploy Azure Bastion host. Set false to destroy it while keeping the code."
  type        = bool
  default     = false
}

variable "public_domain" {
  description = "Public DNS zone for chat.<domain> / argocd.<domain>."
  type        = string
}
