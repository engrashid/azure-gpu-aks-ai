# ── Cluster identity ───────────────────────────────────────────────────────────

output "cluster_id" {
  description = "Azure resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — used by azurerm_federated_identity_credential and any additional WI bindings"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

# ── Kubelet identity ───────────────────────────────────────────────────────────

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity (used for additional role assignments)"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
}

# ── Infrastructure ─────────────────────────────────────────────────────────────

output "node_resource_group" {
  description = "Auto-generated resource group that contains AKS node VMs, disks, and NICs"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

# ── Kubeconfig (sensitive) ─────────────────────────────────────────────────────
# These values are marked sensitive. They are intended for use with the
# Kubernetes / Helm providers in the same root module.
# With local_account_disabled=true and AAD RBAC enabled, the client_certificate
# and client_key fields will be empty — authentication occurs via AAD tokens.

output "host" {
  description = "AKS API server endpoint (for kubernetes provider host argument)"
  sensitive   = true
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  sensitive   = true
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
}

output "client_certificate" {
  description = "Base64-encoded client certificate (empty when local_account_disabled=true)"
  sensitive   = true
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
}

output "client_key" {
  description = "Base64-encoded client key (empty when local_account_disabled=true)"
  sensitive   = true
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster (sensitive — do not log)"
  sensitive   = true
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
}
