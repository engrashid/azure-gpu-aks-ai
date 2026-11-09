# =============================================================================
# Providers
#
# azurerm    — Azure infrastructure
# helm       — ArgoCD Helm install  (needs AKS cluster to be up)
# kubernetes — Kubernetes secrets / namespaces
# kubectl    — ArgoCD CRD resources (AppProject, Application)
#
# helm / kubernetes / kubectl use kubelogin exec auth because
# local_account_disabled=true on the cluster (AAD-only access).
# Prerequisites: az login && kubelogin installed.
# When var.argocd_enabled=false these providers are still initialised but
# no resources are created, so the cluster does not need to exist.
# =============================================================================

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
  subscription_id = var.subscription_id
}

# ── Kubernetes / Helm / Kubectl ────────────────────────────────────────────────
# These three providers share the same auth configuration.
# host / cluster_ca_certificate come from module.aks outputs after the cluster
# is created. On a first apply with argocd_enabled=false the cluster does not
# yet exist; Terraform will still initialise providers but will not connect
# because no resources use them.

locals {
  # kubelogin args for Azure CLI login mode. The server-id is the fixed AKS
  # AAD server application ID (same for all clusters).
  kubelogin_args = [
    "get-token",
    "--login", "azurecli",
    "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630",
    "--tenant-id", var.tenant_id,
    "--environment", "AzurePublicCloud",
  ]
}

provider "helm" {
  kubernetes {
    host                   = module.aks.host
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args        = local.kubelogin_args
    }
  }
}

provider "kubernetes" {
  host                   = module.aks.host
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = local.kubelogin_args
  }
}

provider "kubectl" {
  host                   = module.aks.host
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = local.kubelogin_args
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}
