#!/usr/bin/env bash
# =============================================================================
# ArgoCD Bootstrap — aks-qwen-dev
#
# One-time manual bootstrap. After this script completes successfully,
# GitOps takes over and all further changes are made via the gitops/ tree.
#
# Usage:
#   export AZDO_PAT=<your-pat>
#   export GITOPS_REPO_URL=https://dev.azure.com/<org>/<proj>/_git/azure-gpu-aks-ai
#   bash scripts/bootstrap-argocd.sh
#
# Optional flags:
#   --gitops-repo-url URL     Override GITOPS_REPO_URL env var
#   --argocd-version VERSION  Override ArgoCD Helm chart version (default 7.7.5)
#   --skip-install            Skip Helm install; only apply projects + root-app
# =============================================================================
set -euo pipefail

# ── Colours & logging ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ts()      { date '+%H:%M:%S'; }
info()    { echo -e "$(ts) ${BLUE}[INFO ]${RESET} $*"; }
success() { echo -e "$(ts) ${GREEN}[PASS ]${RESET} $*"; }
warn()    { echo -e "$(ts) ${YELLOW}[WARN ]${RESET} $*"; }
die()     { echo -e "$(ts) ${RED}[FAIL ]${RESET} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ── Defaults ───────────────────────────────────────────────────────────────────
ARGOCD_VERSION="${ARGOCD_VERSION:-9.5.2}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
SKIP_INSTALL=false
EXPECTED_CONTEXT_SUBSTR="aks-qwen-dev"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitops-repo-url)
      GITOPS_REPO_URL="$2"; shift 2 ;;
    --argocd-version)
      ARGOCD_VERSION="$2"; shift 2 ;;
    --skip-install)
      SKIP_INSTALL=true; shift ;;
    -h|--help)
      grep '^#' "$0" | head -20 | sed 's/^# //; s/^#//'
      exit 0 ;;
    *)
      die "Unknown argument: $1\nUsage: $0 [--gitops-repo-url URL] [--argocd-version VERSION] [--skip-install]" ;;
  esac
done

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   ArgoCD Bootstrap — aks-qwen-dev                   ║${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║  Chart version : ${ARGOCD_VERSION}$(printf '%*s' $((36 - ${#ARGOCD_VERSION})) '')║${RESET}"
echo -e "${BOLD}║  Skip install  : ${SKIP_INSTALL}$(printf '%*s' $((36 - ${#SKIP_INSTALL})) '')║${RESET}"
echo -e "${BOLD}║  Repo root     : ${REPO_ROOT:0:36}$(printf '%*s' $((36 - ${#REPO_ROOT} < 0 ? 0 : 36 - ${#REPO_ROOT})) '')║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Preflight checks ───────────────────────────────────────────────────────────
header "Preflight Checks"

# Required tools
for tool in kubectl helm; do
  command -v "${tool}" > /dev/null 2>&1 \
    || die "'${tool}' not found in PATH. Install it and retry."
  success "${tool}: $(${tool} version --client --short 2>/dev/null | head -1 || ${tool} version 2>&1 | head -1)"
done

# kubectl context
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
[[ -n "${CURRENT_CONTEXT}" ]] \
  || die "No active kubectl context. Run: az aks get-credentials --resource-group rg-qwen-ephemeral-dev --name aks-qwen-dev --overwrite-existing && kubelogin convert-kubeconfig -l azurecli"
[[ "${CURRENT_CONTEXT}" == *"${EXPECTED_CONTEXT_SUBSTR}"* ]] \
  || die "kubectl context '${CURRENT_CONTEXT}' does not contain '${EXPECTED_CONTEXT_SUBSTR}'.\nSwitch context: az aks get-credentials --resource-group rg-qwen-ephemeral-dev --name aks-qwen-dev --overwrite-existing"
success "kubectl context: ${CURRENT_CONTEXT}"

# Cluster reachable
kubectl cluster-info --request-timeout=10s > /dev/null 2>&1 \
  || die "kubectl cluster-info failed.\nCheck: (1) your public IP is in api_server_authorized_ip_ranges, (2) kubelogin is configured."
success "API server reachable"

# Required namespaces (created by validate-and-test.sh)
for ns in argocd platform gpu-inference; do
  kubectl get namespace "${ns}" --no-headers > /dev/null 2>&1 \
    || die "Namespace '${ns}' does not exist.\nRun the validate script first: bash scripts/validate-and-test.sh"
  success "namespace '${ns}' exists"
done

# PAT (only needed when not skipping install)
if [[ "${SKIP_INSTALL}" == false ]]; then
  [[ -n "${AZDO_PAT:-}" ]] \
    || die "AZDO_PAT is not set.\nExport your Azure DevOps / GitHub Personal Access Token:\n  export AZDO_PAT=<token>"
  info "AZDO_PAT is set (${#AZDO_PAT} chars)"
fi

# Repo URL
if [[ -z "${GITOPS_REPO_URL}" ]]; then
  die "GITOPS_REPO_URL is not set.\nExport it or pass --gitops-repo-url:\n  export GITOPS_REPO_URL=https://dev.azure.com/<org>/<proj>/_git/azure-gpu-aks-ai"
fi
[[ "${GITOPS_REPO_URL}" =~ ^https?:// ]] \
  || die "GITOPS_REPO_URL does not look like a valid https URL: ${GITOPS_REPO_URL}"
success "GITOPS_REPO_URL: ${GITOPS_REPO_URL}"

# Required files
VALUES_FILE="${REPO_ROOT}/gitops/bootstrap/argocd-install-values.yaml"
ROOT_APP="${REPO_ROOT}/gitops/bootstrap/root-app.yaml"
PROJECTS_DIR="${REPO_ROOT}/gitops/projects"

[[ -f "${VALUES_FILE}" ]] || die "Missing: ${VALUES_FILE}"
[[ -f "${ROOT_APP}" ]]    || die "Missing: ${ROOT_APP}"
[[ -d "${PROJECTS_DIR}" ]] || die "Missing directory: ${PROJECTS_DIR}"
success "Required files present"

success "All preflight checks passed"

# ── Pre-create argocd-redis secret ────────────────────────────────────────────
# argocd-install-values.yaml sets redisSecretInit.enabled: false to skip the
# pre-install hook Job. The Job's only purpose is to generate this secret, so
# we create it here with a random password before Helm runs.
# Redis will not start without it, causing --wait to time out.
header "Pre-creating argocd-redis secret"

if kubectl get secret argocd-redis -n argocd > /dev/null 2>&1; then
  info "argocd-redis secret already exists — skipping"
else
  kubectl create secret generic argocd-redis \
    --namespace argocd \
    --from-literal=auth="$(openssl rand -hex 32)"
  success "argocd-redis secret created"
fi

# ── Install ArgoCD via Helm ────────────────────────────────────────────────────
if [[ "${SKIP_INSTALL}" == false ]]; then
  header "Installing ArgoCD (argo/argo-cd chart ${ARGOCD_VERSION})"

  info "Adding argo Helm repo..."
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update argo
  success "Helm repo updated"

  info "Running helm upgrade --install (this may take ~3 minutes)..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version "${ARGOCD_VERSION}" \
    --values "${VALUES_FILE}" \
    --wait \
    --timeout 15m \
    --set "configs.cm.url=http://argocd.local"

  success "ArgoCD chart ${ARGOCD_VERSION} installed"
else
  info "Skipping Helm install (--skip-install flag set)"
fi

# ── Wait for ArgoCD deployments to be Ready ───────────────────────────────────
header "Waiting for ArgoCD Pods Ready"

info "Waiting up to 5 minutes for core deployments..."

for deploy in argocd-server argocd-repo-server argocd-applicationset-controller; do
  kubectl rollout status deployment/"${deploy}" \
    -n argocd \
    --timeout=300s \
    && success "${deploy} Ready" \
    || die "${deploy} did not become Ready within 300s.\nDebug: kubectl describe deployment ${deploy} -n argocd"
done

# argocd-application-controller is a StatefulSet
kubectl rollout status statefulset/argocd-application-controller \
  -n argocd \
  --timeout=300s \
  && success "argocd-application-controller Ready" \
  || die "argocd-application-controller did not become Ready.\nDebug: kubectl describe statefulset argocd-application-controller -n argocd"

# notifications-controller is disabled in values — skip if absent
if kubectl get deployment argocd-notifications-controller -n argocd > /dev/null 2>&1; then
  kubectl rollout status deployment/argocd-notifications-controller \
    -n argocd --timeout=120s \
    && success "argocd-notifications-controller Ready" \
    || warn "argocd-notifications-controller not ready (non-critical — notifications disabled)"
fi

success "All ArgoCD components Ready"

# ── Retrieve and save initial admin password ───────────────────────────────────
header "Admin Password"

PASS_FILE="${REPO_ROOT}/argocd-admin-password.txt"

if kubectl get secret argocd-initial-admin-secret -n argocd > /dev/null 2>&1; then
  kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath='{.data.password}' \
    | base64 --decode \
    > "${PASS_FILE}"
  printf '\n' >> "${PASS_FILE}"   # ensure trailing newline
  chmod 600 "${PASS_FILE}"
  ADMIN_PASSWORD="$(tr -d '[:space:]' < "${PASS_FILE}")"
  success "Admin password saved to ${PASS_FILE} (chmod 600)"
  info    "Password: ${ADMIN_PASSWORD}"
else
  warn "argocd-initial-admin-secret not found — password may have been changed already."
  warn "If you know the password, set it in: ${PASS_FILE}"
  ADMIN_PASSWORD="<see ${PASS_FILE}>"
  touch "${PASS_FILE}"; chmod 600 "${PASS_FILE}"
fi

# ── Repository credential secret ──────────────────────────────────────────────
if [[ "${SKIP_INSTALL}" == false ]]; then
  header "ArgoCD Repository Credential"

  info "Creating repository credential secret for ${GITOPS_REPO_URL}..."

  # Delete previous (idempotent re-run)
  kubectl delete secret argocd-repo-gitops -n argocd --ignore-not-found > /dev/null

  kubectl create secret generic argocd-repo-gitops \
    --namespace argocd \
    --from-literal=type=git \
    --from-literal=url="${GITOPS_REPO_URL}" \
    --from-literal=username=argocd \
    --from-literal=password="${AZDO_PAT}"

  kubectl label secret argocd-repo-gitops \
    -n argocd \
    "argocd.argoproj.io/secret-type=repository" \
    "managed-by=bootstrap-script" \
    --overwrite > /dev/null

  success "Repository credential created"
fi

# ── Apply ArgoCD Projects ──────────────────────────────────────────────────────
header "Applying ArgoCD Projects"

info "Applying manifests from ${PROJECTS_DIR}/..."
kubectl apply -f "${PROJECTS_DIR}/"
success "ArgoCD projects applied"

# ── Apply root Applications (app-of-apps) ─────────────────────────────────────
header "Applying Root Applications"

info "Substituting GITOPS_REPO_URL into root-app.yaml and applying..."

# sed substitution is safe here: URL is validated as https:// above.
# The placeholder string GITOPS_REPO_URL_PLACEHOLDER appears in root-app.yaml.
sed "s|GITOPS_REPO_URL_PLACEHOLDER|${GITOPS_REPO_URL}|g" "${ROOT_APP}" \
  | kubectl apply -f -

success "Root applications applied (platform-root, workloads-root)"

# ── Wait for root Applications to sync ────────────────────────────────────────
header "Waiting for Root Applications — Synced + Healthy"

wait_for_app() {
  local app_name="$1"
  local timeout_s=600
  local interval_s=10
  local elapsed=0

  info "Watching '${app_name}' (timeout ${timeout_s}s)..."

  while [[ ${elapsed} -lt ${timeout_s} ]]; do
    local health sync
    health="$(kubectl get application "${app_name}" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo 'Unknown')"
    sync="$(kubectl get application "${app_name}" -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo 'Unknown')"

    if [[ "${health}" == "Healthy" && "${sync}" == "Synced" ]]; then
      success "'${app_name}': Synced / Healthy"
      return 0
    fi

    info "  ${app_name}: sync=${sync} health=${health} (+${elapsed}s)"
    sleep "${interval_s}"
    elapsed=$(( elapsed + interval_s ))
  done

  warn "'${app_name}' did not reach Synced/Healthy within ${timeout_s}s."
  warn "This is normal if gitops/platform-apps/ and gitops/workload-apps/ are empty."
  warn "Debug: kubectl describe application ${app_name} -n argocd"
  return 0  # non-fatal — operator may be adding apps incrementally
}

# platform-apps and workload-apps directories may be empty at first bootstrap.
# Applications will become Healthy once files are added to those directories.
wait_for_app "platform-root"
wait_for_app "workloads-root"

# ── Success banner ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  Bootstrap Complete                                              ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}Access the ArgoCD UI (port-forward):${RESET}"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  open http://localhost:8080"
echo ""
echo -e "${BOLD}Login credentials:${RESET}"
echo "  Username : admin"
echo "  Password : ${ADMIN_PASSWORD}"
echo "  Saved to : ${PASS_FILE}"
echo ""
echo -e "${BOLD}Watch application sync status:${RESET}"
echo "  kubectl get applications -n argocd"
echo "  kubectl get applications -n argocd -w"
echo ""
echo -e "${BOLD}Force a manual sync:${RESET}"
echo "  kubectl patch application platform-root -n argocd \\"
echo "    --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{}}}'"
echo ""
echo -e "${BOLD}Runbook:${RESET} docs/runbooks/argocd-bootstrap.md"
echo ""
