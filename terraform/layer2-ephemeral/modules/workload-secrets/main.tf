# =============================================================================
# Workload Secrets
#
# Creates the two Kubernetes secrets that cannot be managed by GitOps because
# they contain sensitive values sourced from Azure:
#
#   1. azure-blob-csi-secret  (gpu-inference) — storage account key for vLLM
#      model weight mount via Blob CSI driver.
#
#   2. oauth2-proxy-creds     (oauth2-proxy)  — AAD client secret + stable
#      cookie secret for the oauth2-proxy deployment.
#
# Both secrets are gated on var.enabled so the module is a no-op before
# the AKS cluster exists.
# =============================================================================

# ── Blob CSI secret ────────────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "blob_csi" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "azure-blob-csi-secret"
    namespace = "gpu-inference"
    labels = {
      "managed-by" = "terraform"
    }
  }

  data = {
    azurestorageaccountname = var.storage_account_name
    azurestorageaccountkey  = var.storage_account_key
  }
}

# ── oauth2-proxy cookie secret ─────────────────────────────────────────────────
# Generated once; ignored on subsequent applies so it survives re-applies.

resource "random_password" "cookie_secret" {
  length  = 32
  special = false
}

# ── oauth2-proxy AAD credentials ──────────────────────────────────────────────
# Creates a new client secret on the existing AAD app registration.
# The secret is rotated only when this resource is tainted.

resource "azuread_application_password" "oauth2_proxy" {
  count          = var.enabled ? 1 : 0
  application_id = "/applications/${var.oauth2_proxy_app_object_id}"
  display_name   = "oauth2-proxy-k8s-terraform"
  end_date       = "2099-01-01T00:00:00Z"
}

resource "kubernetes_secret_v1" "oauth2_proxy" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "oauth2-proxy-creds"
    namespace = "oauth2-proxy"
    labels = {
      "managed-by" = "terraform"
    }
  }

  data = {
    client-id     = var.oauth2_proxy_client_id
    client-secret = azuread_application_password.oauth2_proxy[0].value
    cookie-secret = random_password.cookie_secret.result
  }

  lifecycle {
    ignore_changes = [data]
  }
}
