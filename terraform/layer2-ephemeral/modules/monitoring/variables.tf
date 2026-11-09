variable "resource_group_name" {
  description = "Resource group that will contain the monitoring resources"
  type        = string
}

variable "location" {
  description = "Azure region"
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

variable "grafana_admin_group_object_id" {
  description = <<-EOT
    Azure AD group object ID granted the built-in 'Grafana Admin' role on the
    Managed Grafana instance. Without this assignment no AAD user can sign in
    to the Grafana UI — the Grafana resource will be deployed but inaccessible.
  EOT
  type        = string
}
