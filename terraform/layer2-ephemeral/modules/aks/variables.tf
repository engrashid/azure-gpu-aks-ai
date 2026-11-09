# ── Naming ─────────────────────────────────────────────────────────────────────

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

# ── Placement ──────────────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Resource group that will contain the AKS cluster"
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

# ── Networking (from networking module outputs) ────────────────────────────────

variable "aks_subnet_id" {
  description = "Resource ID of the AKS spoke subnet (all node pools land here)"
  type        = string
}

# ── Layer 1 cross-references ───────────────────────────────────────────────────

variable "acr_id" {
  description = "Resource ID of the Layer 1 ACR (kubelet identity gets AcrPull)"
  type        = string
}

variable "vllm_identity_id" {
  description = "Resource ID of the Layer 1 vLLM user-assigned managed identity"
  type        = string
}

# ── Observability ──────────────────────────────────────────────────────────────

variable "law_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for OMS agent, Defender, and diagnostics"
  type        = string
}

# ── AAD / RBAC ─────────────────────────────────────────────────────────────────

variable "tenant_id" {
  description = "Azure AD tenant ID used for AAD RBAC"
  type        = string
}

variable "admin_group_object_ids" {
  description = "Azure AD group object IDs granted Cluster Admin via AAD RBAC"
  type        = list(string)
}

# ── API server access (PUBLIC cluster) ────────────────────────────────────────
# This cluster uses a public API server with IP allowlist instead of a private
# endpoint, enabling direct kubectl from a developer laptop without a jumpbox.
# List every developer's current public IP as a /32.
# Quick lookup: curl -s https://api.ipify.org

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    CIDR ranges permitted to reach the public API server.
    Include each developer's laptop public IP as a /32.
    Find your current IP with: curl -s https://api.ipify.org
  EOT
  type        = list(string)

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0
    error_message = "At least one authorized IP range is required. Add your laptop public IP as X.X.X.X/32."
  }
}

# ── Cluster ────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane and default node pool"
  type        = string
  default     = "1.30"
}

variable "os_sku_default" {
  description = "OS SKU for all node pools. Ubuntu2204 is broadly available; Ubuntu2404 if the region supports it."
  type        = string
  default     = "Ubuntu2204"

  validation {
    condition     = contains(["Ubuntu2204", "Ubuntu2404", "AzureLinux"], var.os_sku_default)
    error_message = "os_sku_default must be Ubuntu2204, Ubuntu2404, or AzureLinux."
  }
}

# ── GPU node pool ──────────────────────────────────────────────────────────────

variable "gpu_zone" {
  description = "Availability zone for the GPU node pool (Standard_NC4as_T4_v3 availability varies by zone)"
  type        = string
  default     = "1"
}

variable "spoke_vnet_id" {
  description = "Resource ID of the spoke VNet. AKS control-plane identity needs Network Contributor here to provision internal load balancers."
  type        = string
}

variable "app_gateway_id" {
  description = "Resource ID of the Application Gateway. Passed to the AGIC addon; AGIC MSI is granted Contributor on this resource."
  type        = string
}
