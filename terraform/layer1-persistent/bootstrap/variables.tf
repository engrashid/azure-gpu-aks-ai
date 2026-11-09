variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (used in resource names and tags)"
  type        = string
  default     = "dev"
}

variable "prefix" {
  description = "Short name prefix used in all resource names"
  type        = string
  default     = "qwen"
}

variable "cost_center" {
  description = "Cost-center value for the cost_center tag"
  type        = string
  default     = "experimental"
}
