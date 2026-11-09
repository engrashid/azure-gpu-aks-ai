# layer2-ephemeral — Ephemeral Infrastructure

Layer 2 owns every Azure resource that is **created and destroyed on demand**.
Layer 1 persistent resources (ACR, Key Vault, model storage, managed identity)
are referenced read-only via `terraform_remote_state`.

```
layer2-ephemeral/
├── versions.tf / providers.tf / backend.tf
├── main.tf          remote state + resource group + 3 module calls
├── variables.tf / locals.tf / outputs.tf
├── terraform.tfvars.example
└── modules/
    ├── networking/  Hub-spoke VNet, Firewall, Bastion, DNS, PEs, NSGs, UDR
    ├── monitoring/  Log Analytics + Azure Managed Grafana
    └── aks/         Cluster + 3 node pools + workload identity + diagnostics
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | ≥ 1.9 |
| Azure CLI | any recent |
| kubectl | any recent |

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## Step 1 — Get your laptop's public IP

The AKS API server is public with an explicit IP allowlist. You **must** add
your current laptop IP before apply or every `kubectl` call will time out.

```bash
curl -s https://api.ipify.org
# example: 203.0.113.42
```

---

## Step 2 — Create terraform.tfvars

```bash
cd terraform/layer2-ephemeral
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:
- `subscription_id` and `tenant_id`
- `admin_group_object_ids` — AAD group for `kubectl` admin access
- `grafana_admin_group_object_id` — AAD group for Grafana UI access
- `api_server_authorized_ip_ranges` — your laptop IP as `X.X.X.X/32`

---

## Full apply sequence (first time)

### A. Bootstrap Layer 1 (once per subscription)

```bash
cd terraform/layer1-persistent/bootstrap
terraform init
terraform apply -var-file="terraform.tfvars"
```

### B. Apply Layer 1 (once per environment)

See `terraform/layer1-persistent/bootstrap/README.md` for the full walkthrough.
Summary (abbreviated — use the bootstrap README for authoritative steps):

```bash
cd terraform/layer1-persistent

# Move backend.tf aside so terraform import can use local state
# (terraform import does not accept -backend=false)
mv backend.tf backend.tf.disabled
terraform init

terraform import -var-file="terraform.tfvars" azurerm_resource_group.persistent \
  "/subscriptions/<SUB>/resourceGroups/rg-qwen-persistent-dev"
terraform import -var-file="terraform.tfvars" azurerm_storage_account.tfstate \
  "/subscriptions/<SUB>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev"
terraform import -var-file="terraform.tfvars" azurerm_storage_container.tfstate_layer1 \
  "/subscriptions/<SUB>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev/blobServices/default/containers/tfstate-layer1"
terraform import -var-file="terraform.tfvars" azurerm_storage_container.tfstate_layer2 \
  "/subscriptions/<SUB>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev/blobServices/default/containers/tfstate-layer2"

terraform apply -var-file="terraform.tfvars"

mv backend.tf.disabled backend.tf
terraform init -migrate-state      # migrates local → remote backend
terraform plan  -var-file="terraform.tfvars"   # should show no changes
```

### C. Apply Layer 2

```bash
cd terraform/layer2-ephemeral
terraform init
terraform plan -var-file="terraform.tfvars" -out=layer2.tfplan
terraform apply layer2.tfplan
```

Approximate apply time: **20–35 minutes** (Firewall: ~10 min, AKS: ~10 min,
Bastion: ~5 min, Grafana: ~3 min).

---

## Getting kubeconfig after apply

Terraform prints a ready-to-run command in the `get_credentials_command` output:

```bash
terraform output -raw get_credentials_command | bash
```

Or run it manually:

```bash
az aks get-credentials \
  --resource-group rg-qwen-ephemeral-dev \
  --name aks-qwen-dev \
  --overwrite-existing
```

Verify access (requires membership in `admin_group_object_ids`):

```bash
kubectl get nodes
kubectl get pods -A
```

---

## Updating the API server IP allowlist

When your laptop IP changes (new network, new lease, etc.):

```bash
# Find new IP
curl -s https://api.ipify.org

# Option 1: Terraform (recommended — keeps state in sync)
# Edit api_server_authorized_ip_ranges in terraform.tfvars, then:
terraform apply -var-file="terraform.tfvars" \
  -target='module.aks.azurerm_kubernetes_cluster.main'
# Takes ~30 s, no node disruption.

# Option 2: Azure CLI (emergency, bypasses Terraform state)
az aks update \
  --resource-group rg-qwen-ephemeral-dev \
  --name aks-qwen-dev \
  --api-server-authorized-ip-ranges "203.0.113.42/32,198.51.100.7/32"
# Remember to also update terraform.tfvars or the next terraform apply
# will revert to the old list.
```

---

## GPU node pool and NVIDIA drivers

**AKS installs GPU drivers automatically.** Do not deploy the NVIDIA GPU
Operator driver component or any manual driver DaemonSet — it will conflict
with the AKS-managed installation.

The GPU node pool (`Standard_NC4as_T4_v3`) scales **to zero** when idle.
Nodes are provisioned on demand when a pod with the matching toleration
(`nvidia.com/gpu=present:NoSchedule`) is scheduled.

```yaml
# Required on any GPU workload pod spec
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Equal"
    value: "present"
    effect: "NoSchedule"
nodeSelector:
  gpu-type: "nvidia-t4"
```

Verify GPU allocation after a node is provisioned:

```bash
kubectl get nodes -l gpu-type=nvidia-t4
kubectl describe node <gpu-node> | grep -A5 "Allocatable"
# Should show:  nvidia.com/gpu: 1
```

---

## ⚠️  Log Analytics daily quota

`daily_quota_gb = 5` stops all ingestion when 5 GB is consumed in a UTC day.
AKS control-plane logs (kube-apiserver, kube-audit) **will be dropped** when
the cap is hit. See `modules/monitoring/README.md` for monitoring instructions
and how to raise or remove the cap.

---

## Workload Identity contract

The `azurerm_federated_identity_credential` in the AKS module binds the vLLM
managed identity to **exactly**:

| Field | Value |
|---|---|
| Namespace | `gpu-inference` |
| ServiceAccount | `vllm-sa` |

ArgoCD **must** create these with those exact names and annotate the SA:

```yaml
azure.workload.identity/client-id: "<terraform output -raw vllm_identity_client_id>"
```

See `modules/aks/README.md` for the full SA manifest.

---

## Destroying Layer 2

```bash
cd terraform/layer2-ephemeral
terraform destroy -var-file="terraform.tfvars"
```

Layer 1 resources (ACR images, Key Vault secrets, model weights) are
unaffected. After a fresh `terraform apply`, the cluster reconnects to the
same persistent storage and registry.

**Do not run `terraform destroy` in `layer1-persistent/` unless you intend
to permanently delete all model weights and ACR images.**

---

## Required Azure RBAC for the operator

| Permission | Scope |
|---|---|
| Contributor | subscription or `rg-qwen-ephemeral-dev` |
| User Access Administrator | subscription or `rg-qwen-ephemeral-dev` |
| Storage Blob Data Contributor | `stqwentfstatedev` (remote state) |
| User Access Administrator | Layer 1 RG (for workload identity federation) |
