variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID (required for Key Vault)"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name; drives resource names and tags"
  type        = string
  default     = "dev"
}

variable "prefix" {
  description = "Short name prefix used across all resource names"
  type        = string
  default     = "qwen"
}

variable "cost_center" {
  description = "Cost-center value for the cost_center tag"
  type        = string
  default     = "experimental"
}

variable "additional_admin_member_object_ids" {
  description = "Object IDs of extra AAD users/SPs to add to aks-admins and grafana-admins groups"
  type        = list(string)
  default     = []
}

variable "additional_reader_member_object_ids" {
  description = "Object IDs of extra AAD users/SPs to add to aks-vllm-readers group"
  type        = list(string)
  default     = []
}
