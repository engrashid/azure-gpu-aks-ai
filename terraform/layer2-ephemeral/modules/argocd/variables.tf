# ── Feature flag ──────────────────────────────────────────────────────────────

variable "enabled" {
  description = "Set to true to install and manage ArgoCD. Set to false to skip the entire module (e.g. first apply before cluster exists)."
  type        = bool
  default     = true
}

# ── Chart ─────────────────────────────────────────────────────────────────────

variable "argocd_chart_version" {
  description = "argo/argo-cd Helm chart version to install."
  type        = string
  default     = "9.5.2"
}

# ── Git repository ─────────────────────────────────────────────────────────────

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repository ArgoCD will clone (e.g. https://dev.azure.com/<org>/<proj>/_git/<repo>)."
  type        = string
}

variable "azdo_pat" {
  description = "Personal Access Token with Code (Read) scope on the GitOps repository. Stored as a Kubernetes secret; never written to Terraform state in plaintext."
  type        = string
  sensitive   = true
}

# ── AAD ────────────────────────────────────────────────────────────────────────

variable "aks_admins_group_object_id" {
  description = "Object ID of the AKS Admins AAD group. Injected into AppProject role bindings. Get from: terraform -chdir=terraform/layer1-persistent output -raw aks_admins_group_object_id"
  type        = string
  default     = ""
}

# ── Redis ─────────────────────────────────────────────────────────────────────

variable "redis_password" {
  description = "Password for the ArgoCD Redis instance. Leave empty to auto-generate a random 32-byte hex password (recommended)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "public_domain" {
  description = "Public DNS zone for chat.<domain> / argocd.<domain>."
  type        = string
}
