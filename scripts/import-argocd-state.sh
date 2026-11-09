#!/usr/bin/env bash
# =============================================================================
# Import existing ArgoCD resources into Terraform state
#
# Run this ONCE against an existing ArgoCD installation before running
# terraform apply with argocd_enabled=true. It brings all live resources under
# Terraform management without recreating or disrupting them.
#
# Prerequisites:
#   - terraform init already run in terraform/layer2-ephemeral/
#   - kubectl context pointing at aks-qwen-dev
#   - ArgoCD fully installed (all pods Running)
#   - terraform.tfvars present with argocd_enabled=true and correct values
#
# Usage:
#   cd terraform/layer2-ephemeral
#   bash ../../scripts/import-argocd-state.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO ]${RESET} $*"; }
success() { echo -e "${GREEN}[PASS ]${RESET} $*"; }
die()     { echo -e "${RED}[FAIL ]${RESET} $*" >&2; exit 1; }

# Must be run from terraform/layer2-ephemeral/
[[ -f "main.tf" ]] || die "Run this script from terraform/layer2-ephemeral/ (current: $(pwd))"

import() {
  local addr="$1" id="$2"
  if terraform state show "${addr}" > /dev/null 2>&1; then
    info "Already in state — skipping: ${addr}"
  else
    info "Importing ${addr} ..."
    terraform import "${addr}" "${id}"
    success "Imported: ${addr}"
  fi
}

echo ""
echo "━━━ ArgoCD Terraform State Import ━━━"
echo ""

# ── Helm release ───────────────────────────────────────────────────────────────
import 'module.argocd.helm_release.argocd[0]' 'argocd/argocd'

# ── Kubernetes secrets ─────────────────────────────────────────────────────────
import 'module.argocd.kubernetes_secret_v1.redis[0]'     'argocd/argocd-redis'
import 'module.argocd.kubernetes_secret_v1.repo_cred[0]' 'argocd/argocd-repo-gitops'

# ── AppProjects ────────────────────────────────────────────────────────────────
# alekc/kubectl import ID format: apiVersion//Kind//name//namespace  (double-slash separators)
import 'module.argocd.kubectl_manifest.platform_project[0]'  'argoproj.io/v1alpha1//AppProject//platform//argocd'
import 'module.argocd.kubectl_manifest.workloads_project[0]' 'argoproj.io/v1alpha1//AppProject//workloads//argocd'

# ── Root Applications ──────────────────────────────────────────────────────────
# alekc/kubectl for_each keys are the full API server path returned by the
# kubectl_file_documents manifests map.
import 'module.argocd.kubectl_manifest.root_apps["/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/platform-root"]'  'argoproj.io/v1alpha1//Application//platform-root//argocd'
import 'module.argocd.kubectl_manifest.root_apps["/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/workloads-root"]' 'argoproj.io/v1alpha1//Application//workloads-root//argocd'

echo ""
echo "━━━ Import complete ━━━"
echo ""
echo "Next step: run terraform plan to verify zero diff."
echo "  terraform plan -var-file=terraform.tfvars"
echo ""
echo "If plan shows the Redis secret data will change, that is safe —"
echo "Terraform will rotate the password once. Redis restarts in <10s."
echo ""
