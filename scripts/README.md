# scripts/validate-and-test.sh — Usage Guide

Full-cycle validation, drift detection, idempotency testing, and ArgoCD
cluster prep in a single script. Runs entirely from your laptop.

---

## Setup

```bash
chmod +x scripts/validate-and-test.sh
```

### Prerequisites

| Tool | Minimum | Install (macOS) |
|---|---|---|
| bash | 4.0 | `brew install bash` (macOS ships with 3.2) |
| terraform | 1.9 | `brew install terraform` |
| az (Azure CLI) | 2.60 | `brew install azure-cli` |
| kubectl | 1.29 | `brew install kubectl` |
| helm | 3.14 | `brew install helm` |
| jq | 1.6 | `brew install jq` |
| curl | any | pre-installed |
| python3 | any | `brew install python3` |
| timeout (optional) | — | `brew install coreutils` (provides `gtimeout`) |

**macOS bash note:** The system bash at `/bin/bash` is version 3.2 (GPL2
licensing constraint). Install bash 5 via Homebrew and ensure it is first
in your PATH, or invoke the script explicitly:

```bash
/opt/homebrew/bin/bash scripts/validate-and-test.sh [options]
```

### Azure authentication

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## Quick start

```bash
# 1. Find your laptop's public IP
curl -s https://api.ipify.org

# 2. Create tfvars (if not already done)
cp terraform/layer2-ephemeral/terraform.tfvars.example \
   terraform/layer2-ephemeral/terraform.tfvars
# Edit terraform.tfvars: set subscription_id, tenant_id, IPs, group IDs

# 3. Run full validation + 2 idempotency cycles
scripts/validate-and-test.sh
```

---

## Usage

```
scripts/validate-and-test.sh [options]

Options:
  --layer1-dir DIR    Path to layer1-persistent  (default: ./terraform/layer1-persistent)
  --layer2-dir DIR    Path to layer2-ephemeral   (default: ./terraform/layer2-ephemeral)
  --cycles N          Number of destroy/recreate cycles (default: 2)
  --skip-destroy      Apply + validate + prep ArgoCD; leave cluster running
  --drift-only        Plan-only drift check on existing deployed state
  --cost-only         Print monthly cost estimate and exit
  --refresh-ip        Update api_server_authorized_ip_ranges with current IP, exit
```

---

## Common scenarios

### Apply and leave cluster running (day-to-day dev)

```bash
scripts/validate-and-test.sh --skip-destroy
```

Runs: preflight → Layer 1 validate → apply → drift check → az CLI validate →
kubeconfig → kubectl validate → ArgoCD namespace/SA prep

The cluster stays running. Output includes the Grafana endpoint and a reminder
to run destroy when done.

### Daily IP update (when your laptop gets a new public IP)

```bash
scripts/validate-and-test.sh --refresh-ip
# Updates terraform.tfvars and prints the apply command

# Then push the change to AKS (~30 seconds, no node disruption):
cd terraform/layer2-ephemeral
terraform apply -var-file=terraform.tfvars \
  -target='module.aks.azurerm_kubernetes_cluster.main'
```

Or, if you need immediate access (bypasses Terraform state):

```bash
az aks update \
  --resource-group rg-qwen-ephemeral-dev \
  --name aks-qwen-dev \
  --api-server-authorized-ip-ranges "$(curl -s https://api.ipify.org)/32"
# ⚠️ Remember to also update terraform.tfvars or the next `terraform apply`
# will revert to the old IP list.
```

### Drift check only (after manual portal changes)

```bash
# Assumes layer2 is already deployed
scripts/validate-and-test.sh --drift-only
```

Runs terraform plan on both layers with `-detailed-exitcode`. Exit code 0 =
clean. Exit code 2 = drift detected (plan is printed and saved to `logs/`).

### Print cost estimate

```bash
scripts/validate-and-test.sh --cost-only
```

### Single idempotency cycle (faster CI integration)

```bash
scripts/validate-and-test.sh --cycles 1
```

### Full 2-cycle idempotency test (pre-merge / weekly)

```bash
scripts/validate-and-test.sh --cycles 2
```

Approximate duration per cycle: **apply ~20–35 min + destroy ~15–20 min = ~1 hour per cycle**.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All checks passed |
| 1 | Validation or drift failure |
| 2 | Missing tool or failed preflight |
| 3 | Timeout (apply > 45 min or destroy > 30 min) |
| 4 | User input error (missing tfvars, bad argument) |

---

## Log files

Every run creates a timestamped log file:

```
logs/validate-20240115-142301.log    full run output (no color codes)
logs/drift-cycle-1.txt               full plan output when drift is detected
logs/drift-cycle-2.txt               ...
```

The `logs/` directory is created automatically. Add it to `.gitignore`:

```
/logs/*.log
/logs/drift-*.txt
```

---

## Timeouts

| Operation | Timeout |
|---|---|
| terraform apply | 45 min |
| terraform destroy | 30 min |
| drift check (plan) | 10 min |
| kubectl cluster-info | 15 sec |

If `timeout` / `gtimeout` is not installed, timeouts are not enforced but
the script still runs. Install coreutils for enforcement: `brew install coreutils`.

---

## Troubleshooting

### kubectl times out immediately after apply

```
[FAIL] kubectl cluster-info timed out (15s)
[WARN] Most likely cause: your laptop IP is not in api_server_authorized_ip_ranges
```

Fix:

```bash
scripts/validate-and-test.sh --refresh-ip
# Then apply the change (see output for the exact command)
```

### Drift detected immediately after apply

```
[FAIL] DRIFT DETECTED — plan shows changes after a clean apply
```

Common culprits in this stack and their fixes:

| Resource | Drifting attribute | Fix |
|---|---|---|
| `azurerm_kubernetes_cluster` | `oidc_issuer_enabled` | Already set explicitly — check provider version |
| `azurerm_kubernetes_cluster` | `auto_scaler_profile` fields | Provider re-orders on read; add `ignore_changes` |
| `azurerm_kubernetes_cluster_node_pool` (gpu) | `node_count` | Already in `ignore_changes` — check if provider version changed |
| `azurerm_firewall` | `management_ip_configuration` | Provider may re-read in different order; pin provider |
| Any resource | Tags | Azure adds system tags; add `ignore_changes = [tags]` if needed |

Read the drift plan saved to `logs/drift-cycle-N.txt` to identify the exact resource and attribute.

### terraform init fails with backend error

```
Error: Failed to get existing workspaces
```

Layer 1 bootstrap has not been run, or the storage account doesn't exist:

```bash
cd terraform/layer1-persistent/bootstrap
terraform init
terraform apply -var-file=terraform.tfvars
```

Then follow the migration steps in `terraform/layer1-persistent/bootstrap/README.md`.

### az aks get-credentials fails with permission error

The Terraform operator account needs `Azure Kubernetes Service Cluster Admin Role`
on the cluster, or membership in one of the `admin_group_object_ids` groups:

```bash
az role assignment create \
  --role "Azure Kubernetes Service Cluster Admin Role" \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "$(az aks show -g rg-qwen-ephemeral-dev -n aks-qwen-dev --query id -o tsv)"
```

### GPU nodes never scale up

1. Check quota: `az vm list-usage --location eastus | jq '.[] | select(.name.value | contains("NC"))'`
2. Verify taint toleration in the pod spec (see `modules/aks/README.md`)
3. Check autoscaler logs: `kubectl logs -n kube-system -l component=cluster-autoscaler`

### Destroy hangs or fails

Azure Firewall Basic tier is the slowest resource to delete (~10–15 min).
If destroy hangs beyond 30 minutes:

```bash
# Check what's left
az resource list --resource-group rg-qwen-ephemeral-dev --output table

# Force-delete the resource group (bypasses Terraform, destroys everything)
az group delete --name rg-qwen-ephemeral-dev --yes --no-wait
# Then: terraform state rm ... for each deleted resource
```

---

## Architecture of the script

```
main()
  ├── parse_args()
  ├── setup_logging()           creates logs/validate-YYYYMMDD-HHMMSS.log
  ├── detect_timeout_cmd()      handles macOS gtimeout vs Linux timeout
  ├── print_banner()
  │
  ├── [--cost-only]  → cost_estimate() → exit 0
  ├── [--refresh-ip] → check_laptop_ip() → exit 0
  │
  ├── preflight()               tool versions, az auth, tfvars presence
  ├── check_laptop_ip()         warns if current IP not in allowlist
  │
  ├── [--drift-only]
  │     ├── validate_layer1()
  │     └── drift_test_layer2()  → print_summary() → exit
  │
  ├── [--skip-destroy]
  │     ├── validate_layer1()
  │     ├── load_layer1_outputs()
  │     ├── apply_layer2()
  │     ├── drift_test_layer2()
  │     ├── validate_infra_via_az()
  │     ├── get_kubeconfig()
  │     ├── validate_aks_via_kubectl()
  │     └── bootstrap_argocd_prep() → print_summary() → exit
  │
  └── [default: N cycles]
        ├── validate_layer1()
        ├── load_layer1_outputs()
        └── run_cycles(N)
              └── idempotency_cycle(n) × N
                    ├── apply_layer2()
                    ├── drift_test_layer2()   ← core idempotency assertion
                    ├── validate_infra_via_az()
                    ├── get_kubeconfig()
                    ├── validate_aks_via_kubectl()
                    └── destroy_layer2()
                          print_summary() → exit
```
