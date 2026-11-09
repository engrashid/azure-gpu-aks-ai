# ── Azure identity ─────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

# ── Placement ──────────────────────────────────────────────────────────────────

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name; appears in resource names and tags"
  type        = string
  default     = "dev"
}

variable "prefix" {
  description = "Short name prefix used across every resource name"
  type        = string
  default     = "qwen"
}

variable "cost_center" {
  description = "Cost-center value for the cost_center tag"
  type        = string
  default     = "experimental"
}

# ── AKS ────────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes control-plane version (e.g. '1.32')"
  type        = string
  default     = "1.35"
}

variable "gpu_zone" {
  description = "Availability zone for the GPU node pool. Verify Standard_NC4as_T4_v3 quota in that zone."
  type        = string
  default     = "1"
}

# ── API server IP allowlist ────────────────────────────────────────────────────

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    CIDR ranges allowed to reach the public AKS API server.
    MUST include every developer's laptop public IP as a /32.

    Find your current IP:
      curl -s https://api.ipify.org

    To update without a full apply (emergency):
      az aks update \
        --resource-group rg-qwen-ephemeral-dev \
        --name aks-qwen-dev \
        --api-server-authorized-ip-ranges "1.2.3.4/32,5.6.7.8/32"

    Normal update path: change this variable and run terraform apply.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0
    error_message = "At least one authorized IP range is required. Add your laptop public IP as X.X.X.X/32."
  }
}

# ── Observability ──────────────────────────────────────────────────────────────

# ── ArgoCD ─────────────────────────────────────────────────────────────────────

variable "argocd_enabled" {
  description = "Install and manage ArgoCD via Terraform. Set false on a first apply (cluster does not exist yet), then true once the cluster is up."
  type        = bool
  default     = false
}

variable "argocd_chart_version" {
  description = "argo/argo-cd Helm chart version."
  type        = string
  default     = "9.5.2"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repository ArgoCD will clone."
  type        = string
  default     = ""
}

variable "azdo_pat" {
  description = "Azure DevOps / GitHub PAT with Code (Read) scope on the GitOps repo. Sensitive."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Public endpoints & Entra ID app ───────────────────────────────────────────

variable "public_domain" {
  description = "Public DNS zone for the chat UI and ArgoCD (chat.<domain>, argocd.<domain>). Must match the hosts in gitops/."
  type        = string
  default     = "example.com"
}

variable "oauth2_proxy_client_id" {
  description = "Client (application) ID of the Entra ID app registration used by oauth2-proxy."
  type        = string
}

variable "oauth2_proxy_app_object_id" {
  description = "Object ID of the same Entra ID app registration (used to rotate its client secret)."
  type        = string
}
