variable "enabled" {
  description = "Set false before AKS cluster exists; true once cluster is up."
  type        = bool
  default     = true
}

variable "storage_account_name" {
  description = "Name of the model weights storage account"
  type        = string
}

variable "storage_account_key" {
  description = "Primary access key for the model weights storage account"
  type        = string
  sensitive   = true
}

variable "oauth2_proxy_client_id" {
  description = "AAD application (client) ID for oauth2-proxy"
  type        = string
}

variable "oauth2_proxy_app_object_id" {
  description = "AAD application object ID (not client ID) for oauth2-proxy — used to create the client secret"
  type        = string
}
