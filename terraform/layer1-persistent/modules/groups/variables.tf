variable "prefix" {
  description = "Short name prefix used in group display names (e.g. 'qwen')"
  type        = string
}

variable "additional_admin_member_object_ids" {
  description = "Object IDs of extra AAD users/SPs to add to aks-admins and grafana-admins"
  type        = list(string)
  default     = []
}

variable "additional_reader_member_object_ids" {
  description = "Object IDs of extra AAD users/SPs to add to aks-vllm-readers"
  type        = list(string)
  default     = []
}
