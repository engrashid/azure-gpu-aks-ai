# =============================================================================
# ArgoCD Module
#
# Installs ArgoCD via Helm and wires up the app-of-apps GitOps pattern:
#
#   1. argocd-redis secret   — pre-created (redisSecretInit.enabled=false)
#   2. helm_release argocd   — installs chart, waits for all pods Ready
#   3. argocd-repo-gitops    — PAT credential for ArgoCD to clone the repo
#   4. AppProjects           — platform + workloads RBAC scopes
#   5. Root Applications     — platform-root + workloads-root (app-of-apps)
#
# All resources are gated on var.enabled so the module is a no-op on a
# fresh apply before the AKS cluster exists (set enabled=false initially,
# then re-apply with enabled=true after the cluster is up).
#
# Existing installation: run scripts/import-argocd-state.sh once to bring
# the live resources under Terraform management before the first apply.
# =============================================================================

locals {
  # Substitute the repo URL placeholder in the root-app manifest.
  root_app_yaml = replace(
    file("${path.root}/../../gitops/bootstrap/root-app.yaml"),
    "GITOPS_REPO_URL_PLACEHOLDER",
    var.gitops_repo_url
  )

  # Substitute both placeholders in the AppProject manifests.
  aad_group = var.aks_admins_group_object_id != "" ? var.aks_admins_group_object_id : "<AAD_AKS_ADMINS_GROUP_OBJECT_ID>"
}

# ── Redis password ─────────────────────────────────────────────────────────────
# Auto-generate if not supplied. Stored in Terraform state (sensitive).

resource "random_password" "redis" {
  count   = var.enabled && var.redis_password == "" ? 1 : 0
  length  = 32
  special = false
}

locals {
  redis_password = var.redis_password != "" ? var.redis_password : (
    length(random_password.redis) > 0 ? random_password.redis[0].result : ""
  )
}

# ── argocd-redis secret ────────────────────────────────────────────────────────
# Must exist before helm_release; redisSecretInit.enabled=false skips the
# pre-install Job that would otherwise create this.

resource "kubernetes_secret_v1" "redis" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "argocd-redis"
    namespace = "argocd"
  }

  data = {
    auth = local.redis_password
  }

  lifecycle {
    # Prevent Terraform from rotating the password on every plan after import.
    # To rotate: taint this resource and re-apply.
    ignore_changes = [data]
  }
}

# ── Helm install ───────────────────────────────────────────────────────────────

resource "helm_release" "argocd" {
  count = var.enabled ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = "argocd"

  values = [file("${path.root}/../../gitops/bootstrap/argocd-install-values.yaml")]

  set {
    name  = "configs.cm.url"
    value = "https://argocd.${var.public_domain}"
  }

  wait             = true
  timeout          = 900
  create_namespace = false

  depends_on = [kubernetes_secret_v1.redis]
}

# ── Repository credential ──────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "repo_cred" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "argocd-repo-gitops"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
      "managed-by"                     = "terraform"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = "argocd"
    password = var.azdo_pat
  }

  depends_on = [helm_release.argocd]
}

# ── AppProjects ────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "platform_project" {
  count = var.enabled ? 1 : 0

  yaml_body = replace(
    file("${path.root}/../../gitops/projects/platform-project.yaml"),
    "<AAD_AKS_ADMINS_GROUP_OBJECT_ID>",
    local.aad_group
  )

  server_side_apply = true
  force_conflicts   = true

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "workloads_project" {
  count = var.enabled ? 1 : 0

  yaml_body = replace(
    file("${path.root}/../../gitops/projects/workloads-project.yaml"),
    "<AAD_AKS_ADMINS_GROUP_OBJECT_ID>",
    local.aad_group
  )

  server_side_apply = true
  force_conflicts   = true

  depends_on = [helm_release.argocd]
}

# ── Root Applications (app-of-apps) ───────────────────────────────────────────
# root-app.yaml contains two Application documents separated by ---.
# We split in HCL rather than using kubectl_file_documents so the for_each
# keys ("0", "1") are statically known at plan time. The data source approach
# produces content-hash keys that the kubectl provider can only resolve after
# apply, causing "Invalid for_each argument" errors when AKS is being modified.

locals {
  root_app_documents = [
    for doc in split("\n---\n", local.root_app_yaml) : trimspace(doc)
    if can(regex("^apiVersion:", trimspace(doc)))
  ]
}

resource "kubectl_manifest" "root_apps" {
  for_each = var.enabled ? {
    for idx, doc in local.root_app_documents : tostring(idx) => doc
  } : {}

  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = true

  depends_on = [
    kubectl_manifest.platform_project,
    kubectl_manifest.workloads_project,
  ]
}
