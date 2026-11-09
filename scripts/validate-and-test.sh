#!/usr/bin/env bash
# =============================================================================
# validate-and-test.sh
# Validates Terraform deployment, runs drift detection, tests full
# create-destroy idempotency, and prepares the cluster for ArgoCD bootstrap.
#
# Requirements: bash >= 4.0, az >= 2.60, terraform >= 1.9, kubectl >= 1.29,
#               helm >= 3.14, jq >= 1.6, curl, python3
# Usage: see scripts/README.md
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Bash version guard (associative arrays require bash 4+) ──────────────────
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "ERROR: bash >= 4.0 is required." >&2
  echo "  macOS: brew install bash  (then reopen terminal)" >&2
  exit 2
fi

# =============================================================================
# COLORS & FORMATTING
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# =============================================================================
# DEFAULTS & GLOBALS
# =============================================================================
LAYER1_DIR="./terraform/layer1-persistent"
LAYER2_DIR="./terraform/layer2-ephemeral"
CYCLES=2
SKIP_DESTROY=false
DRIFT_ONLY=false
COST_ONLY=false
REFRESH_IP=false

# Runtime state (populated during execution)
LOG_FILE=""
CURRENT_IP=""
RG_NAME=""
CLUSTER_NAME=""
L1_VLLM_CLIENT_ID=""
TIMEOUT_CMD=""
APPLY_DURATION=0
DESTROY_DURATION=0

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
OVERALL_EXIT=0

# Timeouts (seconds)
readonly TIMEOUT_APPLY=2700     # 45 min
readonly TIMEOUT_DESTROY=1800   # 30 min
readonly TIMEOUT_DRIFT=600      # 10 min
readonly TIMEOUT_KUBECTL=15     # 15 sec

# Cycle tracking arrays
CYCLE_APPLY_TIMES=()
CYCLE_DESTROY_TIMES=()
CYCLE_DRIFT=()
CYCLE_VALIDATE=()
CYCLE_RESULT=()

# Section results (bash 4+)
declare -A SECTION_RESULTS

# =============================================================================
# LOGGING
# =============================================================================
_ts() { date '+%H:%M:%S'; }

# log_*: write colored line to terminal + plain line to log file
log_info() {
  local msg="$*"
  echo -e "[${DIM}$(_ts)${NC}] [${BLUE}INFO ${NC}] ${msg}"
  echo "[$(_ts)] [INFO ] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

log_pass() {
  local msg="$*"
  echo -e "[${DIM}$(_ts)${NC}] [${GREEN}PASS${NC}] ${msg}"
  echo "[$(_ts)] [PASS] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
  PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
  local msg="$*"
  echo -e "[${DIM}$(_ts)${NC}] [${RED}FAIL${NC}] ${msg}" >&2
  echo "[$(_ts)] [FAIL] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
  FAIL_COUNT=$((FAIL_COUNT + 1))
  OVERALL_EXIT=1
}

log_warn() {
  local msg="$*"
  echo -e "[${DIM}$(_ts)${NC}] [${YELLOW}WARN${NC}] ${msg}"
  echo "[$(_ts)] [WARN] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
  WARN_COUNT=$((WARN_COUNT + 1))
}

log_section() {
  local msg="$*"
  echo -e ""
  echo -e "[${DIM}$(_ts)${NC}] ${BOLD}${BLUE}━━━ ${msg} ━━━${NC}"
  echo "" >> "$LOG_FILE" 2>/dev/null || true
  echo "[$(_ts)] ━━━ ${msg} ━━━" >> "$LOG_FILE" 2>/dev/null || true
}

# Pipe terraform/az output through this to log without color codes
log_pipe() { tee -a "$LOG_FILE"; }

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --layer1-dir)   LAYER1_DIR="${2:?--layer1-dir requires a value}";  shift 2 ;;
      --layer2-dir)   LAYER2_DIR="${2:?--layer2-dir requires a value}";  shift 2 ;;
      --cycles)       CYCLES="${2:?--cycles requires a value}";           shift 2 ;;
      --skip-destroy) SKIP_DESTROY=true;                                  shift   ;;
      --drift-only)   DRIFT_ONLY=true;                                    shift   ;;
      --cost-only)    COST_ONLY=true;                                      shift   ;;
      --refresh-ip)   REFRESH_IP=true;                                    shift   ;;
      -h|--help)
        echo "Usage: $0 [options]"
        echo ""
        echo "  --layer1-dir DIR    Path to layer1-persistent (default: ./terraform/layer1-persistent)"
        echo "  --layer2-dir DIR    Path to layer2-ephemeral  (default: ./terraform/layer2-ephemeral)"
        echo "  --cycles N          Create-destroy cycles      (default: 2)"
        echo "  --skip-destroy      Apply + validate only; skip destroy cycles"
        echo "  --drift-only        Run drift check only (assumes infra is deployed)"
        echo "  --cost-only         Print cost estimate and exit"
        echo "  --refresh-ip        Update api_server_authorized_ip_ranges with current IP, then exit"
        exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 4 ;;
    esac
  done

  if ! [[ "$CYCLES" =~ ^[0-9]+$ ]] || [[ "$CYCLES" -lt 1 ]]; then
    echo "ERROR: --cycles must be a positive integer" >&2
    exit 4
  fi
}

# =============================================================================
# SETUP
# =============================================================================
setup_logging() {
  mkdir -p ./logs
  LOG_FILE="./logs/validate-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE"
  log_info "Log file: ${LOG_FILE}"
}

detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    log_warn "Neither 'timeout' nor 'gtimeout' found. Timeout enforcement disabled."
    log_warn "  macOS: brew install coreutils"
    TIMEOUT_CMD=""
  fi
}

# Run a command with timeout; falls back to running without if TIMEOUT_CMD unset
with_timeout() {
  local seconds="$1"; shift
  if [[ -n "$TIMEOUT_CMD" ]]; then
    $TIMEOUT_CMD "${seconds}s" "$@"
  else
    "$@"
  fi
}

# =============================================================================
# BANNER
# =============================================================================
print_banner() {
  local date_str
  date_str="$(date '+%Y-%m-%d %H:%M')"

  echo -e "${BOLD}"
  echo '╔══════════════════════════════════════════════════════╗'
  echo '║   Qwen AKS Experimental — Validation & Idempotency  ║'
  echo '╠══════════════════════════════════════════════════════╣'
  printf  '║  %-52s║\n' "Date:       ${date_str}"
  printf  '║  %-52s║\n' "Layer1:     ${LAYER1_DIR}"
  printf  '║  %-52s║\n' "Layer2:     ${LAYER2_DIR}"
  printf  '║  %-52s║\n' "Cycles:     ${CYCLES}"
  printf  '║  %-52s║\n' "Laptop IP:  ${CURRENT_IP:-detecting...}"
  if $SKIP_DESTROY; then
    printf '║  %-52s║\n' "Mode:       apply + validate (no destroy)"
  elif $DRIFT_ONLY; then
    printf '║  %-52s║\n' "Mode:       drift check only"
  else
    printf '║  %-52s║\n' "Mode:       full idempotency cycles"
  fi
  echo '╚══════════════════════════════════════════════════════╝'
  echo -e "${NC}"

  echo "╔══════════════════════════════════════════════════════╗" >> "$LOG_FILE"
  echo "║   Qwen AKS Experimental — Validation & Idempotency  ║" >> "$LOG_FILE"
  echo "╚══════════════════════════════════════════════════════╝" >> "$LOG_FILE"
  echo "Date: ${date_str} | Layer1: ${LAYER1_DIR} | Layer2: ${LAYER2_DIR} | Cycles: ${CYCLES}" >> "$LOG_FILE"
}

# =============================================================================
# VERSION UTILITIES
# =============================================================================
# Returns 0 (true) if version $1 >= $2 (both in X.Y.Z format)
version_ge() {
  local v1 v2
  IFS='.' read -ra v1 <<< "$1"
  IFS='.' read -ra v2 <<< "$2"
  local i
  for ((i = 0; i < ${#v2[@]}; i++)); do
    local a="${v1[i]:-0}"
    local b="${v2[i]:-0}"
    if ((a > b)); then return 0; fi
    if ((a < b)); then return 1; fi
  done
  return 0
}

# Strip non-numeric prefix (v1.30.0 → 1.30.0, jq-1.6 → 1.6)
strip_version_prefix() { echo "$1" | sed 's/^[^0-9]*//'; }

# =============================================================================
# PREFLIGHT
# =============================================================================
preflight() {
  log_section "Preflight Checks"
  local failed=false

  # ── Tool versions ──────────────────────────────────────────────────────────

  local tools=(
    "az:2.60.0:$(az version 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("azure-cli","0"))' 2>/dev/null || echo 0)"
    "terraform:1.9.0:$(strip_version_prefix "$(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("terraform_version","0"))' 2>/dev/null || terraform version 2>/dev/null | head -1 | awk '{print $2}' | tr -d 'v' || echo 0)")"
    "kubectl:1.29.0:$(strip_version_prefix "$(kubectl version --client -o json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || kubectl version --client --short 2>/dev/null | awk '{print $3}' || echo 0)")"
    "helm:3.14.0:$(strip_version_prefix "$(helm version --short 2>/dev/null | awk '{print $1}' | cut -d'+' -f1 || echo 0)")"
    "jq:1.6:$(strip_version_prefix "$(jq --version 2>/dev/null || echo 0)")"
  )

  for entry in "${tools[@]}"; do
    local tool="${entry%%:*}"
    local rest="${entry#*:}"
    local min_ver="${rest%%:*}"
    local actual_ver="${rest##*:}"

    if ! command -v "$tool" &>/dev/null; then
      log_fail "Tool not found: ${tool} (minimum ${min_ver} required)"
      failed=true
      continue
    fi

    if version_ge "$actual_ver" "$min_ver"; then
      log_pass "${tool} version ${actual_ver} meets minimum (>= ${min_ver})"
    else
      log_fail "${tool} version ${actual_ver} does not meet minimum (>= ${min_ver})"
      failed=true
    fi
  done

  # curl (just presence check)
  if command -v curl &>/dev/null; then
    log_pass "curl is present"
  else
    log_fail "curl not found"
    failed=true
  fi

  # python3 (used for tfvars update)
  if command -v python3 &>/dev/null; then
    log_pass "python3 is present"
  else
    log_fail "python3 not found (required for --refresh-ip)"
    failed=true
  fi

  # ── Azure authentication ────────────────────────────────────────────────────
  local az_account
  set +e
  az_account=$(az account show --output json 2>&1)
  local az_exit=$?
  set -e

  if [[ $az_exit -ne 0 ]]; then
    log_fail "az account show failed — run: az login"
    failed=true
  else
    local sub_name sub_id
    sub_name=$(echo "$az_account" | jq -r '.name // "unknown"')
    sub_id=$(echo "$az_account" | jq -r '.id // "unknown"')
    log_pass "Azure authenticated — subscription: ${sub_name} (${sub_id})"
  fi

  # ── terraform.tfvars ───────────────────────────────────────────────────────
  local tfvars="${LAYER2_DIR}/terraform.tfvars"
  if [[ -f "$tfvars" ]]; then
    log_pass "terraform.tfvars found: ${tfvars}"
  else
    log_fail "terraform.tfvars missing: ${tfvars}"
    log_fail "  Copy the example: cp ${LAYER2_DIR}/terraform.tfvars.example ${tfvars}"
    failed=true
  fi

  # ── logs directory ─────────────────────────────────────────────────────────
  if [[ -d "./logs" ]]; then
    log_pass "logs/ directory exists"
  else
    mkdir -p ./logs
    log_pass "logs/ directory created"
  fi

  if $failed; then
    log_fail "Preflight failed — fix the issues above and re-run"
    SECTION_RESULTS["Preflight"]="FAIL"
    exit 2
  fi

  SECTION_RESULTS["Preflight"]="PASS"
  log_pass "All preflight checks passed"
}

# =============================================================================
# CHECK LAPTOP IP
# =============================================================================
check_laptop_ip() {
  log_section "Laptop IP Check"
  local tfvars="${LAYER2_DIR}/terraform.tfvars"

  # Detect current public IP
  set +e
  CURRENT_IP=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null)
  local curl_exit=$?
  set -e

  if [[ $curl_exit -ne 0 ]] || [[ -z "$CURRENT_IP" ]]; then
    log_warn "Could not detect public IP (network issue or api.ipify.org unreachable)"
    log_warn "  Manual check: curl -s https://api.ipify.org"
    CURRENT_IP="unknown"
    return 0
  fi

  log_info "Current public IP: ${CURRENT_IP}"

  # ── --refresh-ip: update tfvars and exit ────────────────────────────────────
  if $REFRESH_IP; then
    if [[ ! -f "$tfvars" ]]; then
      log_fail "--refresh-ip: ${tfvars} not found"
      exit 4
    fi
    log_info "Updating api_server_authorized_ip_ranges with ${CURRENT_IP}/32 ..."
    cp "${tfvars}" "${tfvars}.bak"
    python3 - "${tfvars}" "${CURRENT_IP}" <<'PYEOF'
import re, sys
tfvars_path, current_ip = sys.argv[1], sys.argv[2]
with open(tfvars_path, 'r') as f:
    content = f.read()
new_val = f'api_server_authorized_ip_ranges = ["{current_ip}/32"]'
pattern = r'api_server_authorized_ip_ranges\s*=\s*\[[^\]]*\]'
if re.search(pattern, content, re.DOTALL):
    new_content = re.sub(pattern, new_val, content, flags=re.DOTALL)
else:
    new_content = content.rstrip('\n') + '\n' + new_val + '\n'
with open(tfvars_path, 'w') as f:
    f.write(new_content)
print(f"Updated: {new_val}")
PYEOF
    log_pass "Updated ${tfvars} with ${CURRENT_IP}/32"
    log_info "Backup saved to ${tfvars}.bak"
    log_info "Run terraform apply to push the change:"
    log_info "  cd ${LAYER2_DIR} && terraform apply -var-file=terraform.tfvars -target='module.aks.azurerm_kubernetes_cluster.main'"
    exit 0
  fi

  # ── Check if current IP is in authorized ranges ────────────────────────────
  if [[ -f "$tfvars" ]]; then
    if grep -q "${CURRENT_IP}" "$tfvars" 2>/dev/null; then
      log_pass "Current IP ${CURRENT_IP} is in api_server_authorized_ip_ranges"
    else
      log_warn "Current IP ${CURRENT_IP} is NOT in api_server_authorized_ip_ranges"
      log_warn "  kubectl commands will time out after apply."
      log_warn "  Fix options:"
      log_warn "    1. Re-run with:  $0 --refresh-ip"
      log_warn "    2. Manual:       add ${CURRENT_IP}/32 to terraform.tfvars"
      log_warn "    3. Emergency:    az aks update --api-server-authorized-ip-ranges ${CURRENT_IP}/32,<others>"
    fi
  fi
}

# =============================================================================
# VALIDATE LAYER 1 (drift check — expects zero changes)
# =============================================================================
validate_layer1() {
  log_section "Layer 1 Validation"
  pushd "$LAYER1_DIR" > /dev/null
  trap 'popd > /dev/null 2>&1 || true' RETURN

  # terraform init
  log_info "terraform init (layer1)..."
  set +e
  terraform init -upgrade=false 2>&1 | log_pipe
  local init_exit="${PIPESTATUS[0]}"
  set -e
  if [[ $init_exit -ne 0 ]]; then
    log_fail "terraform init failed (layer1)"
    SECTION_RESULTS["Layer1 Init"]="FAIL"
    return 1
  fi
  log_pass "terraform init (layer1)"

  # terraform validate
  log_info "terraform validate (layer1)..."
  set +e
  terraform validate 2>&1 | log_pipe
  local validate_exit="${PIPESTATUS[0]}"
  set -e
  if [[ $validate_exit -ne 0 ]]; then
    log_fail "terraform validate failed (layer1)"
    SECTION_RESULTS["Layer1 Validate"]="FAIL"
    return 1
  fi
  log_pass "terraform validate (layer1)"

  # terraform plan — MUST be exit code 0 (no changes)
  log_info "terraform plan -detailed-exitcode (layer1)..."
  local plan_exit=0
  set +e
  with_timeout "$TIMEOUT_DRIFT" \
    terraform plan -detailed-exitcode -out=/tmp/l1.tfplan 2>&1 | log_pipe
  plan_exit="${PIPESTATUS[0]}"
  set -e

  case "$plan_exit" in
    0)
      log_pass "Layer 1 plan: zero drift — no changes required"
      SECTION_RESULTS["Layer1 Drift"]="PASS"
      ;;
    2)
      log_fail "Layer 1 plan: CHANGES DETECTED — Layer 1 has drifted from config"
      log_fail "  Common causes: ACR name change, Key Vault suffix mismatch, manual portal edits"
      log_fail "  Review the plan above and apply if intentional: cd ${LAYER1_DIR} && terraform apply"
      SECTION_RESULTS["Layer1 Drift"]="FAIL"
      ;;
    124)
      log_fail "Layer 1 plan timed out (>${TIMEOUT_DRIFT}s)"
      SECTION_RESULTS["Layer1 Drift"]="TIMEOUT"
      ;;
    *)
      log_fail "Layer 1 plan errored (exit ${plan_exit})"
      SECTION_RESULTS["Layer1 Drift"]="FAIL"
      ;;
  esac

  # Verify required outputs exist
  log_info "Verifying Layer 1 outputs..."
  local required_outputs=("acr_id" "keyvault_id" "model_storage_account_id" "vllm_identity_id" "resource_group_name")
  set +e
  local outputs_json
  outputs_json=$(terraform output -json 2>/dev/null)
  local out_exit=$?
  set -e

  if [[ $out_exit -ne 0 ]] || [[ -z "$outputs_json" ]]; then
    log_warn "Could not read Layer 1 outputs (may not be applied yet)"
  else
    local all_outputs_ok=true
    for key in "${required_outputs[@]}"; do
      local val
      val=$(echo "$outputs_json" | jq -r --arg k "$key" '.[$k].value // empty' 2>/dev/null || true)
      if [[ -n "$val" ]] && [[ "$val" != "null" ]]; then
        log_pass "Layer 1 output present: ${key}"
      else
        log_fail "Layer 1 output missing or null: ${key}"
        all_outputs_ok=false
      fi
    done
    if $all_outputs_ok; then
      SECTION_RESULTS["Layer1 Outputs"]="PASS"
    else
      SECTION_RESULTS["Layer1 Outputs"]="FAIL"
    fi
  fi
}

# =============================================================================
# LOAD LAYER 1 OUTPUTS (into globals for use by later functions)
# =============================================================================
load_layer1_outputs() {
  pushd "$LAYER1_DIR" > /dev/null
  trap 'popd > /dev/null 2>&1 || true' RETURN
  set +e
  L1_VLLM_CLIENT_ID=$(terraform output -raw vllm_identity_client_id 2>/dev/null || echo "")
  set -e
  if [[ -n "$L1_VLLM_CLIENT_ID" ]]; then
    log_pass "Layer 1 vLLM client ID loaded: ${L1_VLLM_CLIENT_ID:0:8}..."
  else
    log_warn "Layer 1 vllm_identity_client_id not available — workload identity annotation will be skipped"
  fi
}

# =============================================================================
# APPLY LAYER 2
# =============================================================================
apply_layer2() {
  log_section "Apply Layer 2"
  pushd "$LAYER2_DIR" > /dev/null
  trap 'popd > /dev/null 2>&1 || true' RETURN

  log_info "terraform init (layer2)..."
  set +e
  terraform init -upgrade=false 2>&1 | log_pipe
  local init_exit="${PIPESTATUS[0]}"
  set -e
  if [[ $init_exit -ne 0 ]]; then
    log_fail "terraform init failed (layer2)"; return 1
  fi
  log_pass "terraform init (layer2)"

  log_info "terraform validate (layer2)..."
  set +e
  terraform validate 2>&1 | log_pipe
  local val_exit="${PIPESTATUS[0]}"
  set -e
  if [[ $val_exit -ne 0 ]]; then
    log_fail "terraform validate failed (layer2)"; return 1
  fi
  log_pass "terraform validate (layer2)"

  log_info "terraform plan (layer2)..."
  set +e
  terraform plan -out=/tmp/l2.tfplan 2>&1 | log_pipe
  local plan_exit="${PIPESTATUS[0]}"
  set -e
  if [[ $plan_exit -ne 0 ]]; then
    log_fail "terraform plan failed (layer2, exit ${plan_exit})"; return 1
  fi
  log_pass "terraform plan (layer2)"

  log_info "terraform apply (layer2) — timeout ${TIMEOUT_APPLY}s (~45 min)..."
  local start_ts
  start_ts=$(date +%s)

  set +e
  with_timeout "$TIMEOUT_APPLY" \
    terraform apply -auto-approve /tmp/l2.tfplan 2>&1 | log_pipe
  local apply_exit="${PIPESTATUS[0]}"
  set -e

  local end_ts
  end_ts=$(date +%s)
  APPLY_DURATION=$((end_ts - start_ts))

  if [[ $apply_exit -eq 124 ]]; then
    log_fail "terraform apply TIMED OUT after ${TIMEOUT_APPLY}s"
    SECTION_RESULTS["Apply"]="TIMEOUT"
    exit 3
  fi
  if [[ $apply_exit -ne 0 ]]; then
    log_fail "terraform apply failed (exit ${apply_exit})"
    SECTION_RESULTS["Apply"]="FAIL"
    return 1
  fi

  log_pass "terraform apply completed in ${APPLY_DURATION}s"

  # Extract outputs for use in later functions
  set +e
  RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-qwen-ephemeral-dev")
  CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "aks-qwen-dev")
  set -e

  log_pass "Resource group: ${RG_NAME}"
  log_pass "AKS cluster:    ${CLUSTER_NAME}"
  SECTION_RESULTS["Apply"]="PASS"
}

# =============================================================================
# DRIFT TEST LAYER 2 (core idempotency check)
# =============================================================================
drift_test_layer2() {
  log_section "Drift Detection (Layer 2)"
  pushd "$LAYER2_DIR" > /dev/null
  trap 'popd > /dev/null 2>&1 || true' RETURN

  log_info "Running terraform plan -detailed-exitcode (timeout ${TIMEOUT_DRIFT}s)..."
  log_info "Expected exit code: 0 (zero drift = true idempotency)"

  local drift_exit=0
  local drift_log="./logs/drift-cycle-${1:-0}.txt"

  set +e
  with_timeout "$TIMEOUT_DRIFT" \
    terraform plan -detailed-exitcode 2>&1 | tee "$drift_log" | log_pipe
  drift_exit="${PIPESTATUS[0]}"
  set -e

  case "$drift_exit" in
    0)
      log_pass "ZERO DRIFT — terraform plan shows no changes (true idempotency confirmed)"
      SECTION_RESULTS["Drift (cycle ${1:-})"]="PASS"
      return 0
      ;;
    2)
      log_fail "DRIFT DETECTED — plan shows changes after a clean apply"
      log_fail "  Full plan saved to: ${drift_log}"
      log_fail ""
      log_fail "  Common culprits in this stack:"
      log_fail "    • azurerm_kubernetes_cluster: oidc_issuer_enabled default changed in AKS 1.34"
      log_fail "    • auto_scaler_profile: provider re-orders fields on read"
      log_fail "    • gpu nodepool: min_count=0 triggers node_count computed attr"
      log_fail "    • azurerm_firewall: management_ip_configuration re-read"
      log_fail "    • resource tags: provider normalises case or adds system tags"
      log_fail ""
      log_fail "  Fix: add lifecycle { ignore_changes = [...] } to the drifting resource"
      SECTION_RESULTS["Drift (cycle ${1:-})"]="FAIL"
      return 1
      ;;
    124)
      log_fail "Drift check TIMED OUT (>${TIMEOUT_DRIFT}s)"
      SECTION_RESULTS["Drift (cycle ${1:-})"]="TIMEOUT"
      return 1
      ;;
    *)
      log_fail "Drift check errored (exit ${drift_exit}) — see ${drift_log}"
      SECTION_RESULTS["Drift (cycle ${1:-})"]="FAIL"
      return 1
      ;;
  esac
}

# =============================================================================
# VALIDATE INFRASTRUCTURE VIA AZURE CLI
# =============================================================================
validate_infra_via_az() {
  log_section "Infrastructure Validation (az CLI)"

  if [[ -z "$RG_NAME" ]] || [[ -z "$CLUSTER_NAME" ]]; then
    log_fail "RG_NAME or CLUSTER_NAME not set — was apply_layer2() called first?"
    return 1
  fi

  local all_ok=true

  # ── AKS cluster ─────────────────────────────────────────────────────────────
  log_info "Checking AKS cluster: ${CLUSTER_NAME}..."

  local aks_json
  set +e
  aks_json=$(az aks show \
    --resource-group "$RG_NAME" \
    --name "$CLUSTER_NAME" \
    --output json 2>&1)
  local aks_exit=$?
  set -e

  if [[ $aks_exit -ne 0 ]]; then
    log_fail "az aks show failed — cluster may not exist yet"
    all_ok=false
  else
    local prov_state
    prov_state=$(echo "$aks_json" | jq -r '.provisioningState')
    if [[ "$prov_state" == "Succeeded" ]]; then
      log_pass "AKS provisioningState: Succeeded"
    else
      log_fail "AKS provisioningState: ${prov_state} (expected Succeeded)"
      all_ok=false
    fi

    local private_cluster
    private_cluster=$(echo "$aks_json" | jq -r '.apiServerAccessProfile.enablePrivateCluster // false')
    if [[ "$private_cluster" == "false" ]]; then
      log_pass "AKS: public API server confirmed (Option A)"
    else
      log_fail "AKS: privateClusterEnabled=${private_cluster} (expected false for Option A)"
      all_ok=false
    fi

    local auth_ip_count
    auth_ip_count=$(echo "$aks_json" | jq -r '(.apiServerAccessProfile.authorizedIpRanges // []) | length')
    if [[ "$auth_ip_count" -gt 0 ]]; then
      log_pass "AKS: ${auth_ip_count} authorized IP range(s) configured"
    else
      log_fail "AKS: no authorized IP ranges set (api_server_authorized_ip_ranges is empty)"
      all_ok=false
    fi

    local oidc_url
    oidc_url=$(echo "$aks_json" | jq -r '.oidcIssuerProfile.issuerUrl // empty')
    if [[ -n "$oidc_url" ]]; then
      log_pass "AKS: OIDC issuer URL present (workload identity ready)"
    else
      log_fail "AKS: OIDC issuer URL missing"
      all_ok=false
    fi
  fi

  # ── AKS node pools ───────────────────────────────────────────────────────────
  log_info "Checking AKS node pools..."
  set +e
  local pools_json
  pools_json=$(az aks nodepool list \
    --resource-group "$RG_NAME" \
    --cluster-name "$CLUSTER_NAME" \
    --output json 2>&1)
  local pools_exit=$?
  set -e

  if [[ $pools_exit -ne 0 ]]; then
    log_fail "az aks nodepool list failed"
    all_ok=false
  else
    local pool_count
    pool_count=$(echo "$pools_json" | jq -r 'length')
    if [[ "$pool_count" -eq 3 ]]; then
      log_pass "AKS: 3 node pools present (system, user, gpu)"
    else
      log_fail "AKS: expected 3 node pools, found ${pool_count}"
      all_ok=false
    fi

    # Verify pool names
    for pool_name in "system" "user" "gpu"; do
      local found
      found=$(echo "$pools_json" | jq -r --arg n "$pool_name" 'map(select(.name == $n)) | length')
      if [[ "$found" -eq 1 ]]; then
        log_pass "AKS node pool present: ${pool_name}"
      else
        log_fail "AKS node pool missing: ${pool_name}"
        all_ok=false
      fi
    done

    # GPU pool min_count == 0
    local gpu_min
    gpu_min=$(echo "$pools_json" | jq -r '.[] | select(.name=="gpu") | .minCount // "N/A"')
    if [[ "$gpu_min" == "0" ]]; then
      log_pass "AKS gpu pool: minCount=0 (scale-to-zero enabled)"
    else
      log_warn "AKS gpu pool: minCount=${gpu_min} (expected 0 for cost efficiency)"
    fi
  fi

  # ── Azure Firewall ───────────────────────────────────────────────────────────
  log_info "Checking Azure Firewall..."
  local fw_name="afw-qwen-dev"
  set +e
  local fw_state
  fw_state=$(az network firewall show \
    --resource-group "$RG_NAME" \
    --name "$fw_name" \
    --query 'provisioningState' \
    --output tsv 2>&1)
  local fw_exit=$?
  set -e

  if [[ $fw_exit -ne 0 ]]; then
    log_fail "az network firewall show failed (${fw_name}) — may not exist or wrong RG"
    all_ok=false
  elif [[ "$fw_state" == "Succeeded" ]]; then
    log_pass "Azure Firewall provisioningState: Succeeded"
  else
    log_fail "Azure Firewall provisioningState: ${fw_state}"
    all_ok=false
  fi

  # ── Azure Bastion ────────────────────────────────────────────────────────────
  log_info "Checking Azure Bastion..."
  local bas_name="bas-qwen-dev"
  set +e
  local bas_state
  bas_state=$(az network bastion show \
    --resource-group "$RG_NAME" \
    --name "$bas_name" \
    --query 'provisioningState' \
    --output tsv 2>&1)
  local bas_exit=$?
  set -e

  if [[ $bas_exit -ne 0 ]]; then
    log_fail "az network bastion show failed (${bas_name})"
    all_ok=false
  elif [[ "$bas_state" == "Succeeded" ]]; then
    log_pass "Azure Bastion provisioningState: Succeeded"
  else
    log_fail "Azure Bastion provisioningState: ${bas_state}"
    all_ok=false
  fi

  # ── Private DNS zones ────────────────────────────────────────────────────────
  log_info "Checking private DNS zones..."
  local expected_zones=("privatelink.azurecr.io" "privatelink.vaultcore.azure.net" "privatelink.blob.core.windows.net")
  set +e
  local dns_json
  dns_json=$(az network private-dns zone list \
    --resource-group "$RG_NAME" \
    --output json 2>&1)
  local dns_exit=$?
  set -e

  if [[ $dns_exit -ne 0 ]]; then
    log_fail "az network private-dns zone list failed"
    all_ok=false
  else
    local zone_count
    zone_count=$(echo "$dns_json" | jq -r 'length')
    if [[ "$zone_count" -ge 3 ]]; then
      log_pass "Private DNS: ${zone_count} zones present"
    else
      log_fail "Private DNS: expected >= 3 zones, found ${zone_count}"
      all_ok=false
    fi
    for zone in "${expected_zones[@]}"; do
      local found
      found=$(echo "$dns_json" | jq -r --arg z "$zone" 'map(select(.name == $z)) | length')
      if [[ "$found" -eq 1 ]]; then
        log_pass "DNS zone present: ${zone}"
      else
        log_fail "DNS zone missing: ${zone}"
        all_ok=false
      fi
    done
  fi

  # ── Private endpoints ────────────────────────────────────────────────────────
  log_info "Checking private endpoints..."
  set +e
  local pe_json
  pe_json=$(az network private-endpoint list \
    --resource-group "$RG_NAME" \
    --output json 2>&1)
  local pe_exit=$?
  set -e

  if [[ $pe_exit -ne 0 ]]; then
    log_fail "az network private-endpoint list failed"
    all_ok=false
  else
    local pe_count
    pe_count=$(echo "$pe_json" | jq -r 'length')
    if [[ "$pe_count" -ge 3 ]]; then
      log_pass "Private endpoints: ${pe_count} present"
    else
      log_fail "Private endpoints: expected >= 3, found ${pe_count}"
      all_ok=false
    fi

    local failed_pes
    failed_pes=$(echo "$pe_json" | jq -r '.[] | select(.provisioningState != "Succeeded") | .name' | tr '\n' ' ')
    if [[ -z "$failed_pes" ]]; then
      log_pass "All private endpoints: provisioningState Succeeded"
    else
      log_fail "Private endpoints not Succeeded: ${failed_pes}"
      all_ok=false
    fi
  fi

  if $all_ok; then
    SECTION_RESULTS["Infra Validation"]="PASS"
  else
    SECTION_RESULTS["Infra Validation"]="FAIL"
  fi
}

# =============================================================================
# GET KUBECONFIG
# =============================================================================
get_kubeconfig() {
  log_section "kubeconfig & API Connectivity"

  if [[ -z "$RG_NAME" ]] || [[ -z "$CLUSTER_NAME" ]]; then
    pushd "$LAYER2_DIR" > /dev/null
    trap 'popd > /dev/null 2>&1 || true' RETURN
    set +e
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-qwen-ephemeral-dev")
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "aks-qwen-dev")
    set -e
  fi

  log_info "Fetching kubeconfig for ${CLUSTER_NAME}..."
  set +e
  az aks get-credentials \
    --resource-group "$RG_NAME" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing 2>&1 | log_pipe
  local kc_exit=$?
  set -e

  if [[ $kc_exit -ne 0 ]]; then
    log_fail "az aks get-credentials failed"
    SECTION_RESULTS["kubeconfig"]="FAIL"
    return 1
  fi
  log_pass "kubeconfig written successfully"

  # Test API connectivity (15s timeout)
  log_info "Testing kubectl cluster-info (timeout ${TIMEOUT_KUBECTL}s)..."
  set +e
  with_timeout "$TIMEOUT_KUBECTL" \
    kubectl cluster-info 2>&1 | log_pipe
  local ci_exit="${PIPESTATUS[0]}"
  set -e

  if [[ $ci_exit -eq 0 ]]; then
    log_pass "kubectl cluster-info succeeded — API server reachable"
    SECTION_RESULTS["kubeconfig"]="PASS"
  elif [[ $ci_exit -eq 124 ]]; then
    log_fail "kubectl cluster-info timed out (${TIMEOUT_KUBECTL}s)"
    log_warn "  Most likely cause: your laptop IP (${CURRENT_IP}) is not in api_server_authorized_ip_ranges"
    log_warn "  Fix: run $0 --refresh-ip"
    SECTION_RESULTS["kubeconfig"]="TIMEOUT"
    return 1
  else
    log_fail "kubectl cluster-info failed (exit ${ci_exit})"
    log_warn "  Check: kubectl config current-context"
    SECTION_RESULTS["kubeconfig"]="FAIL"
    return 1
  fi
}

# =============================================================================
# VALIDATE AKS VIA KUBECTL
# =============================================================================
validate_aks_via_kubectl() {
  log_section "AKS Node Validation (kubectl)"

  # Get all nodes as JSON once
  local nodes_json
  set +e
  nodes_json=$(kubectl get nodes -o json 2>/dev/null)
  local nodes_exit=$?
  set -e

  if [[ $nodes_exit -ne 0 ]]; then
    log_fail "kubectl get nodes failed"
    SECTION_RESULTS["kubectl Nodes"]="FAIL"
    return 1
  fi

  # ── System nodes: expect 2 Ready ─────────────────────────────────────────────
  local sys_total sys_ready
  sys_total=$(echo "$nodes_json" | jq -r '[.items[] | select(.metadata.labels["agentpool"] == "system")] | length')
  sys_ready=$(echo "$nodes_json" | jq -r '[.items[] | select(.metadata.labels["agentpool"] == "system") | .status.conditions[] | select(.type=="Ready" and .status=="True")] | length')

  if [[ "$sys_total" -eq 2 ]] && [[ "$sys_ready" -eq 2 ]]; then
    log_pass "System nodes: 2/2 Ready"
  else
    log_fail "System nodes: ${sys_ready}/${sys_total} Ready (expected 2/2)"
    SECTION_RESULTS["kubectl Nodes"]="FAIL"
  fi

  # ── User nodes: expect >= 2 Ready ────────────────────────────────────────────
  local user_total user_ready
  user_total=$(echo "$nodes_json" | jq -r '[.items[] | select(.metadata.labels["agentpool"] == "user")] | length')
  user_ready=$(echo "$nodes_json" | jq -r '[.items[] | select(.metadata.labels["agentpool"] == "user") | .status.conditions[] | select(.type=="Ready" and .status=="True")] | length')

  if [[ "$user_total" -ge 2 ]] && [[ "$user_ready" -ge 2 ]]; then
    log_pass "User nodes: ${user_ready}/${user_total} Ready (min 2 satisfied)"
  else
    log_fail "User nodes: ${user_ready}/${user_total} Ready (expected >= 2 Ready)"
    SECTION_RESULTS["kubectl Nodes"]="FAIL"
  fi

  # ── GPU nodes: expect 0 (scale-to-zero) ──────────────────────────────────────
  local gpu_total
  gpu_total=$(echo "$nodes_json" | jq -r '[.items[] | select(.metadata.labels["agentpool"] == "gpu")] | length')

  if [[ "$gpu_total" -eq 0 ]]; then
    log_pass "GPU nodes: 0 present (scale-to-zero confirmed)"
  else
    log_warn "GPU nodes: ${gpu_total} present (expected 0 at startup — may have scaled up)"
  fi

  # ── Namespace inventory ───────────────────────────────────────────────────────
  log_info "Current namespaces:"
  set +e
  local ns_list
  ns_list=$(kubectl get namespaces --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null | tr '\n' '  ')
  set -e
  log_info "  ${ns_list}"

  if echo "$ns_list" | grep -q "argocd"; then
    log_warn "argocd namespace already exists (pre-existing install)"
  else
    log_info "argocd namespace absent (expected — ArgoCD bootstrap is Phase 3)"
  fi

  # Set section result based on pass/fail count changes
  if [[ $FAIL_COUNT -eq 0 ]] || ! echo "${SECTION_RESULTS[*]}" | grep -q "FAIL"; then
    SECTION_RESULTS["kubectl Nodes"]="${SECTION_RESULTS['kubectl Nodes']:-PASS}"
  fi
  SECTION_RESULTS["kubectl Nodes"]="${SECTION_RESULTS['kubectl Nodes']:-PASS}"
}

# =============================================================================
# BOOTSTRAP ARGOCD PREP
# =============================================================================
bootstrap_argocd_prep() {
  log_section "ArgoCD Bootstrap Preparation"
  log_info "Creating namespaces and vLLM ServiceAccount..."

  local all_ok=true

  # ── Namespaces (idempotent via --dry-run=client) ───────────────────────────
  local namespaces=("argocd" "gpu-inference" "platform")
  for ns in "${namespaces[@]}"; do
    set +e
    kubectl create namespace "$ns" \
      --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - 2>&1 | log_pipe
    local ns_exit="${PIPESTATUS[1]}"
    set -e
    if [[ $ns_exit -eq 0 ]]; then
      log_pass "Namespace ready: ${ns}"
    else
      log_fail "Failed to create namespace: ${ns}"
      all_ok=false
    fi
  done

  # ── vLLM ServiceAccount in gpu-inference ─────────────────────────────────
  # CONTRACT: namespace=gpu-inference, name=vllm-sa
  # The federated credential in workload-identity.tf references exactly this
  # subject: system:serviceaccount:gpu-inference:vllm-sa
  local client_id_annotation=""
  if [[ -n "$L1_VLLM_CLIENT_ID" ]]; then
    client_id_annotation="  annotations:
    azure.workload.identity/client-id: \"${L1_VLLM_CLIENT_ID}\""
    log_info "Annotating vllm-sa with client-id: ${L1_VLLM_CLIENT_ID:0:8}..."
  else
    log_warn "vLLM client ID unknown — ServiceAccount will be created WITHOUT annotation"
    log_warn "  Add annotation manually: kubectl annotate sa vllm-sa -n gpu-inference \\"
    log_warn "    azure.workload.identity/client-id=<client-id>"
  fi

  set +e
  kubectl apply -f - 2>&1 | log_pipe << YAML_EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vllm-sa
  namespace: gpu-inference
  labels:
    azure.workload.identity/use: "true"
${client_id_annotation}
YAML_EOF
  local sa_exit="${PIPESTATUS[1]}"
  set -e

  if [[ $sa_exit -eq 0 ]]; then
    log_pass "ServiceAccount vllm-sa created/updated in gpu-inference"
  else
    log_fail "Failed to create ServiceAccount vllm-sa"
    all_ok=false
  fi

  if $all_ok; then
    SECTION_RESULTS["ArgoCD Prep"]="PASS"
    log_pass "Cluster ready for ArgoCD bootstrap"
    log_info ""
    log_info "  Next steps:"
    log_info "    1. Install ArgoCD into the argocd namespace"
    log_info "    2. Deploy vLLM via ArgoCD ApplicationSet pointing at gpu-inference"
    log_info "    3. The vllm-sa ServiceAccount is pre-created with WI annotation"
  else
    SECTION_RESULTS["ArgoCD Prep"]="FAIL"
  fi
}

# =============================================================================
# DESTROY LAYER 2
# =============================================================================
destroy_layer2() {
  log_section "Destroy Layer 2"
  pushd "$LAYER2_DIR" > /dev/null
  trap 'popd > /dev/null 2>&1 || true' RETURN

  log_info "terraform destroy -auto-approve (timeout ${TIMEOUT_DESTROY}s / ~30 min)..."
  local start_ts
  start_ts=$(date +%s)

  set +e
  with_timeout "$TIMEOUT_DESTROY" \
    terraform destroy -auto-approve 2>&1 | log_pipe
  local destroy_exit="${PIPESTATUS[0]}"
  set -e

  local end_ts
  end_ts=$(date +%s)
  DESTROY_DURATION=$((end_ts - start_ts))

  if [[ $destroy_exit -eq 124 ]]; then
    log_fail "terraform destroy TIMED OUT after ${TIMEOUT_DESTROY}s"
    SECTION_RESULTS["Destroy"]="TIMEOUT"
    exit 3
  fi
  if [[ $destroy_exit -ne 0 ]]; then
    log_fail "terraform destroy failed (exit ${destroy_exit})"
    SECTION_RESULTS["Destroy"]="FAIL"
    return 1
  fi
  log_pass "terraform destroy completed in ${DESTROY_DURATION}s"

  # Verify resource group is gone
  local target_rg="${RG_NAME:-rg-qwen-ephemeral-dev}"
  log_info "Verifying resource group deleted: ${target_rg}..."
  set +e
  az group show --name "$target_rg" --output none 2>/dev/null
  local rg_exit=$?
  set -e

  if [[ $rg_exit -ne 0 ]]; then
    log_pass "Resource group ${target_rg}: confirmed deleted"
    SECTION_RESULTS["Destroy"]="PASS"
  else
    log_warn "Resource group ${target_rg} still exists — may be deleting asynchronously"
    log_warn "  Check: az group show --name ${target_rg} --query provisioningState"
    SECTION_RESULTS["Destroy"]="WARN"
  fi
  RG_NAME=""
  CLUSTER_NAME=""
}

# =============================================================================
# IDEMPOTENCY CYCLE
# =============================================================================
idempotency_cycle() {
  local cycle_num="${1:?cycle number required}"
  local cycle_result="PASS"
  log_section "Idempotency Cycle ${cycle_num} / ${CYCLES}"

  # 1 — Apply
  apply_layer2
  CYCLE_APPLY_TIMES+=("$APPLY_DURATION")

  # 2 — Drift check (must be zero immediately after apply)
  if drift_test_layer2 "$cycle_num"; then
    CYCLE_DRIFT+=("PASS")
  else
    CYCLE_DRIFT+=("FAIL")
    cycle_result="FAIL"
  fi

  # 3 — Infra validation via az CLI
  if validate_infra_via_az; then
    CYCLE_VALIDATE+=("PASS")
  else
    CYCLE_VALIDATE+=("FAIL")
    cycle_result="FAIL"
  fi

  # 4 — kubeconfig
  if get_kubeconfig; then
    # 5 — kubectl node validation
    validate_aks_via_kubectl || cycle_result="FAIL"
  else
    cycle_result="FAIL"
  fi

  # 6 — Destroy
  if destroy_layer2; then
    CYCLE_DESTROY_TIMES+=("$DESTROY_DURATION")
  else
    CYCLE_DESTROY_TIMES+=(0)
    cycle_result="FAIL"
  fi

  CYCLE_RESULT+=("$cycle_result")

  if [[ "$cycle_result" == "PASS" ]]; then
    log_pass "Cycle ${cycle_num} complete — PASS (apply: ${APPLY_DURATION}s, destroy: ${DESTROY_DURATION}s)"
  else
    log_fail "Cycle ${cycle_num} complete — FAIL"
  fi
}

# =============================================================================
# RUN N CYCLES
# =============================================================================
run_cycles() {
  for ((i = 1; i <= CYCLES; i++)); do
    idempotency_cycle "$i"
  done
}

# =============================================================================
# COST ESTIMATE
# =============================================================================
cost_estimate() {
  echo ""
  echo -e "${BOLD}${BLUE}Monthly Cost Estimate (East US, Pay-As-You-Go)${NC}"
  echo "Based on list prices; Reserved Instances / Savings Plans not applied."
  echo ""
  printf "${BOLD}%-44s %12s %12s %12s${NC}\n" "Resource" "Unit (\$)" "Units/mo" "Total (\$)"
  echo "──────────────────────────────────────────────────────────────────────────────"
  printf "%-44s %12s %12s %12s\n" "Standard_D2s_v3 × 2  (system pool)" "0.096/h" "730 × 2" "\$140.16"
  printf "%-44s %12s %12s %12s\n" "Standard_D4s_v3 × 2  (user pool)"   "0.192/h" "730 × 2" "\$280.32"
  printf "%-44s %12s %12s %12s\n" "Standard_NC4as_T4_v3 (8 h/day GPU)" "0.526/h" "176 h"   "\$92.58"
  printf "%-44s %12s %12s %12s\n" "Azure Firewall Basic"               "0.395/h" "730 h"   "\$288.35"
  printf "%-44s %12s %12s %12s\n" "Azure Bastion Standard"             "0.290/h" "730 h"   "\$211.70"
  printf "%-44s %12s %12s %12s\n" "Log Analytics  (~20 GB/mo)"         "2.76/GB" "20 GB"   "\$55.20"
  printf "%-44s %12s %12s %12s\n" "Azure Managed Grafana Standard"     "fixed"   "—"       "\$9.00"
  printf "%-44s %12s %12s %12s\n" "Storage / Key Vault / ACR"         "varies"  "—"       "~\$20.00"
  echo "──────────────────────────────────────────────────────────────────────────────"
  printf "${BOLD}%-44s %12s %12s %12s${NC}\n" "TOTAL (approx.)" "" "" "~\$1,097/mo"
  echo ""
  echo "Per-cycle cost estimate (Firewall + Bastion + LAW + AKS running ~30 min):"
  printf "  ( 0.395 + 0.290 + 0.046 + (0.096×2 + 0.192×2) ) × 0.5h ≈ %s\n" "~\$1.50 / cycle"
  echo ""
  echo "Cost reduction levers:"
  echo "  1. Destroy layer2 overnight  — biggest saving (\$700+/mo idle compute)"
  echo "  2. GPU pool min_count=0      — already implemented (scale-to-zero)"
  echo "  3. Switch to Spot VMs        — up to 90% off node compute (interruptions)"
  echo "  4. Reserved Instances (1-yr) — ~40% off on D-series"
  echo "  5. daily_quota_gb=5 on LAW   — already implemented (LAW cap)"
  echo ""
}

# =============================================================================
# PRINT SUMMARY
# =============================================================================
print_summary() {
  local total_checks=$((PASS_COUNT + FAIL_COUNT))
  local end_time
  end_time=$(date '+%Y-%m-%d %H:%M:%S')

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║  VALIDATION SUMMARY                                              ║${NC}"
  echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
  printf "${BOLD}║  %-64s║${NC}\n" "Completed: ${end_time}"
  printf "${BOLD}║  %-64s║${NC}\n" "Log file:  ${LOG_FILE}"
  echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"

  # Print each section result
  for section in \
    "Preflight" \
    "Layer1 Init" "Layer1 Validate" "Layer1 Drift" "Layer1 Outputs" \
    "Apply" "Drift (cycle )" "Infra Validation" "kubeconfig" \
    "kubectl Nodes" "ArgoCD Prep" "Destroy" \
    ; do
    local status="${SECTION_RESULTS[$section]:-}"
    [[ -z "$status" ]] && continue
    local color="$NC"
    case "$status" in
      PASS)    color="$GREEN" ;;
      FAIL)    color="$RED" ;;
      WARN*)   color="$YELLOW" ;;
      TIMEOUT) color="$RED" ;;
    esac
    printf "║  %-44s  ${color}%-16s${NC}  ║\n" "$section" "$status"
  done

  # Print cycle results table if cycles were run
  if [[ ${#CYCLE_RESULT[@]} -gt 0 ]]; then
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BOLD}║  %-8s %-12s %-7s %-10s %-14s %-8s  ║${NC}\n" \
      "Cycle" "Apply(sec)" "Drift" "Validate" "Destroy(sec)" "Result"
    echo -e "╠══════════════════════════════════════════════════════════════════╣"
    for ((i = 0; i < ${#CYCLE_RESULT[@]}; i++)); do
      local ci=$((i + 1))
      local apply_t="${CYCLE_APPLY_TIMES[$i]:-?}"
      local drift_r="${CYCLE_DRIFT[$i]:-?}"
      local val_r="${CYCLE_VALIDATE[$i]:-?}"
      local dest_t="${CYCLE_DESTROY_TIMES[$i]:-?}"
      local res="${CYCLE_RESULT[$i]:-?}"
      local res_color="$NC"
      [[ "$res" == "PASS" ]] && res_color="$GREEN"
      [[ "$res" == "FAIL" ]] && res_color="$RED"
      printf "║  %-8s %-12s %-7s %-10s %-14s ${res_color}%-8s${NC}  ║\n" \
        "$ci" "${apply_t}s" "$drift_r" "$val_r" "${dest_t}s" "$res"
    done
  fi

  echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"

  if [[ $OVERALL_EXIT -eq 0 ]]; then
    printf "${BOLD}║  ${GREEN}%-64s${NC}${BOLD}║${NC}\n" "OVERALL: PASS"
  else
    printf "${BOLD}║  ${RED}%-64s${NC}${BOLD}║${NC}\n" "OVERALL: FAIL"
  fi

  printf "${BOLD}║  %-64s║${NC}\n" \
    "Checks: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings (of ${total_checks} total)"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Mirror to log file (no color)
  {
    echo ""
    echo "══════════ VALIDATION SUMMARY ══════════"
    echo "Completed:  ${end_time}"
    echo "Log file:   ${LOG_FILE}"
    echo "Checks:     ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"
    echo "Overall:    $([ $OVERALL_EXIT -eq 0 ] && echo PASS || echo FAIL)"
  } >> "$LOG_FILE"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  parse_args "$@"
  setup_logging
  detect_timeout_cmd

  # --cost-only is self-contained; no other setup needed
  if $COST_ONLY; then
    cost_estimate
    exit 0
  fi

  # Detect laptop IP early (needed for banner and check)
  set +e
  CURRENT_IP=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")
  set -e

  print_banner

  # --refresh-ip: handle in check_laptop_ip (exits after update)
  if $REFRESH_IP; then
    check_laptop_ip
    exit 0
  fi

  # ── Normal flow ────────────────────────────────────────────────────────────
  preflight
  check_laptop_ip

  # ── drift-only: just run plan checks, no apply/destroy ────────────────────
  if $DRIFT_ONLY; then
    validate_layer1
    log_info "Drift-only mode: running terraform plan on existing layer2 state..."
    log_warn "Drift-only assumes layer2 is already applied. Large plan = not deployed."
    drift_test_layer2 "drift-only"
    print_summary
    exit $OVERALL_EXIT
  fi

  # ── All other modes: start with layer1 validation ─────────────────────────
  validate_layer1
  load_layer1_outputs

  # ── skip-destroy: apply once, validate, leave running ─────────────────────
  if $SKIP_DESTROY; then
    apply_layer2
    drift_test_layer2 "skip-destroy"
    validate_infra_via_az
    get_kubeconfig
    validate_aks_via_kubectl
    bootstrap_argocd_prep
    print_summary

    echo ""
    log_info "━━━ Cluster is running. Useful commands: ━━━"
    log_info "  Grafana:    terraform -chdir=${LAYER2_DIR} output -raw grafana_endpoint"
    log_info "  kubeconfig: already configured in current context"
    log_info "  Nodes:      kubectl get nodes -o wide"
    log_info "  Destroy:    cd ${LAYER2_DIR} && terraform destroy -var-file=terraform.tfvars"
    exit $OVERALL_EXIT
  fi

  # ── Default: full idempotency cycles ──────────────────────────────────────
  run_cycles

  print_summary

  if [[ $OVERALL_EXIT -eq 0 ]]; then
    log_pass "All ${CYCLES} idempotency cycle(s) passed — deployment is fully idempotent"
  else
    log_fail "One or more cycles failed — review the log: ${LOG_FILE}"
  fi

  exit $OVERALL_EXIT
}

main "$@"
