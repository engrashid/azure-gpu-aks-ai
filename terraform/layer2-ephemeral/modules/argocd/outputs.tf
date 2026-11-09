output "admin_password" {
  description = "ArgoCD initial admin password. Rotate via the ArgoCD UI after first login."
  sensitive   = true
  value = var.enabled ? (
    try(
      data.kubernetes_secret_v1.initial_admin[0].data["password"],
      "not-yet-available"
    )
  ) : "disabled"
}

output "port_forward_command" {
  description = "Run this to open the ArgoCD UI on http://localhost:8080"
  value       = var.enabled ? "kubectl port-forward svc/argocd-server -n argocd 8080:80" : "argocd disabled"
}

# ── Data source for admin secret ───────────────────────────────────────────────
# ArgoCD generates this secret during first boot. It may not exist on a
# brand-new install until the server pod is fully Ready.

data "kubernetes_secret_v1" "initial_admin" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }

  depends_on = [helm_release.argocd]
}
