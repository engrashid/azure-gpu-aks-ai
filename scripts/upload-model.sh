#!/usr/bin/env bash
# =============================================================================
# Upload Qwen2.5-7B-Instruct-AWQ model weights to Azure Blob Storage
#
# Downloads the model from Hugging Face and uploads it to the model-weights
# container in the Layer 1 storage account. The blob path must match the
# storage.modelSubPath value in gitops/charts/qwen-api/values.yaml.
#
# Prerequisites:
#   - az CLI logged in  (az login)
#   - python3 + pip (for huggingface_hub)
#   - azcopy (optional, ~3× faster parallel upload)
#
# Usage:
#   bash scripts/upload-model.sh
#
# Environment overrides:
#   HF_TOKEN          Hugging Face access token (not required for Qwen models)
#   LOCAL_MODEL_DIR   Where to download the model (default: /tmp/qwen-model)
#   SKIP_DOWNLOAD     Set to 1 to skip the HF download step (model already local)
# =============================================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
HF_MODEL_ID="Qwen/Qwen2.5-7B-Instruct-AWQ"
BLOB_SUBPATH="qwen2.5-7b-instruct-awq"        # must match storage.modelSubPath in values.yaml

STORAGE_ACCOUNT="stqwenmodelsdev"
CONTAINER="model-weights"
RESOURCE_GROUP="rg-qwen-persistent-dev"
SUBSCRIPTION="${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"

LOCAL_MODEL_DIR="${LOCAL_MODEL_DIR:-/tmp/qwen-model}"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-0}"

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO ]${RESET} $*"; }
success() { echo -e "${GREEN}[PASS ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN ]${RESET} $*"; }
die()     { echo -e "${RED}[FAIL ]${RESET} $*" >&2; exit 1; }

echo ""
echo "━━━ Qwen2.5-7B-Instruct-AWQ Model Upload ━━━"
echo ""

# ── Prerequisite checks ────────────────────────────────────────────────────────
info "Checking prerequisites..."

command -v az > /dev/null || die "az CLI not found. Install: https://aka.ms/installazureclimacos"
az account show --subscription "${SUBSCRIPTION}" > /dev/null 2>&1 \
  || die "Not logged in to Azure subscription ${SUBSCRIPTION}. Run: az login"

# Verify storage account is reachable
az storage account show \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --subscription "${SUBSCRIPTION}" \
  --query "name" -o tsv > /dev/null \
  || die "Cannot reach storage account ${STORAGE_ACCOUNT}. Check az login and subscription."

success "Azure CLI authenticated and storage account reachable."

# ── Download from Hugging Face ─────────────────────────────────────────────────
if [[ "${SKIP_DOWNLOAD}" == "1" ]]; then
  info "SKIP_DOWNLOAD=1 — skipping HF download, using existing: ${LOCAL_MODEL_DIR}"
  [[ -d "${LOCAL_MODEL_DIR}" ]] || die "LOCAL_MODEL_DIR does not exist: ${LOCAL_MODEL_DIR}"
else
  info "Installing/upgrading huggingface_hub..."
  python3 -m pip install -q --upgrade huggingface_hub

  info "Downloading ${HF_MODEL_ID} → ${LOCAL_MODEL_DIR}"
  info "(~5 GB — this takes several minutes on first run)"

  if [[ -n "${HF_TOKEN:-}" ]]; then
    info "Using HF_TOKEN for authenticated download."
  fi

  HF_TOKEN_VALUE="${HF_TOKEN:-}"
  python3 - "${HF_MODEL_ID}" "${LOCAL_MODEL_DIR}" "${HF_TOKEN_VALUE}" <<'PYEOF'
import sys
from huggingface_hub import snapshot_download

repo_id, local_dir, token = sys.argv[1], sys.argv[2], sys.argv[3]

kwargs = {
    "repo_id": repo_id,
    "local_dir": local_dir,
    "local_dir_use_symlinks": False,
    "ignore_patterns": ["*.msgpack", "*.h5", "flax_model*", "tf_model*", "rust_model*"],
}
if token:
    kwargs["token"] = token

print(f"Downloading to: {local_dir}", flush=True)
path = snapshot_download(**kwargs)
print(f"Download complete: {path}", flush=True)
PYEOF

  success "Model downloaded to ${LOCAL_MODEL_DIR}"
fi

# ── Show local model size ──────────────────────────────────────────────────────
MODEL_SIZE=$(du -sh "${LOCAL_MODEL_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
info "Local model size: ${MODEL_SIZE}"

# ── Upload to Azure Blob Storage ───────────────────────────────────────────────
info "Uploading to ${STORAGE_ACCOUNT}/${CONTAINER}/${BLOB_SUBPATH}/ ..."

# Prefer azcopy for parallel uploads (much faster for large files)
if command -v azcopy > /dev/null 2>&1; then
  info "Using azcopy for parallel upload."

  # Generate a short-lived SAS token (2 hours) for the upload
  SAS_EXPIRY=$(date -u -v+2H '+%Y-%m-%dT%H:%MZ' 2>/dev/null \
    || date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')  # macOS vs Linux date

  SAS_TOKEN=$(az storage container generate-sas \
    --account-name "${STORAGE_ACCOUNT}" \
    --name "${CONTAINER}" \
    --permissions rwl \
    --expiry "${SAS_EXPIRY}" \
    --auth-mode login \
    --as-user \
    --subscription "${SUBSCRIPTION}" \
    -o tsv)

  BLOB_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${BLOB_SUBPATH}"

  azcopy copy \
    "${LOCAL_MODEL_DIR}/*" \
    "${BLOB_URL}?${SAS_TOKEN}" \
    --recursive=false \
    --overwrite=ifSourceNewer \
    --log-level=INFO \
    --block-size-mb=128 \
    --cap-mbps=500

else
  warn "azcopy not found — falling back to az storage blob upload-batch (slower)."
  warn "Install azcopy for ~3× faster uploads: brew install azcopy"
  echo ""

  # Retrieve storage account key (shared_access_key_enabled=true in Layer 1)
  info "Fetching storage account key..."
  ACCOUNT_KEY=$(az storage account keys list \
    --account-name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --subscription "${SUBSCRIPTION}" \
    --query "[0].value" -o tsv)

  az storage blob upload-batch \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${ACCOUNT_KEY}" \
    --destination "${CONTAINER}/${BLOB_SUBPATH}" \
    --source "${LOCAL_MODEL_DIR}" \
    --overwrite true \
    --output table
fi

echo ""

# ── Verify upload ──────────────────────────────────────────────────────────────
info "Verifying upload..."

# Reuse key if already set (upload block above may have set it)
ACCOUNT_KEY="${ACCOUNT_KEY:-$(az storage account keys list \
  --account-name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --subscription "${SUBSCRIPTION}" \
  --query "[0].value" -o tsv)}"

BLOB_COUNT=$(az storage blob list \
  --account-name "${STORAGE_ACCOUNT}" \
  --account-key "${ACCOUNT_KEY}" \
  --container-name "${CONTAINER}" \
  --prefix "${BLOB_SUBPATH}/" \
  --query "length(@)" \
  -o tsv)

if [[ "${BLOB_COUNT}" -gt 0 ]]; then
  success "Upload verified: ${BLOB_COUNT} blobs at ${CONTAINER}/${BLOB_SUBPATH}/"
else
  die "Upload verification failed — no blobs found at ${CONTAINER}/${BLOB_SUBPATH}/"
fi

# Show blob listing
info "Blob listing:"
az storage blob list \
  --account-name "${STORAGE_ACCOUNT}" \
  --account-key "${ACCOUNT_KEY}" \
  --container-name "${CONTAINER}" \
  --prefix "${BLOB_SUBPATH}/" \
  --query "[].{name:name, size:properties.contentLength}" \
  --output table

echo ""
echo "━━━ Upload complete ━━━"
echo ""
echo "Model is ready at:"
echo "  https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${BLOB_SUBPATH}/"
echo ""
echo "The Blob CSI driver will mount this path as /mnt/models/${BLOB_SUBPATH}/"
echo "inside the vLLM pod when the qwen-api Helm chart is deployed."
echo ""
echo "Next steps:"
echo "  1. Commit the gitops/envs/dev/qwen-values.yaml changes (clientID is now set)."
echo "  2. Push to trigger ArgoCD sync of the workloads-root app."
echo "  3. Monitor: kubectl get pods -n qwen -w"
echo ""
