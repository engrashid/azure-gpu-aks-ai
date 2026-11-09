# =============================================================================
# Workload Identity Federation — vLLM ServiceAccount
#
# Links the Layer 1 user-assigned managed identity (mi-qwen-vllm-dev) to the
# Kubernetes ServiceAccount that the vLLM pod uses.
#
# CONTRACT — enforced by this federated credential's subject:
#   Namespace:      gpu-inference
#   ServiceAccount: vllm-sa
#
# These names MUST match exactly when ArgoCD creates the namespace and SA.
# The SA must carry the annotation:
#   azure.workload.identity/client-id: <vllm_identity_client_id output>
#
# The federated credential is created in the Layer 1 resource group because
# it is a child resource of the managed identity, which lives there.
# =============================================================================

resource "azurerm_federated_identity_credential" "vllm" {
  name                      = "fc-vllm-${var.environment}"
  user_assigned_identity_id = var.vllm_identity_id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:gpu-inference:vllm-sa"
}
