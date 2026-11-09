# modules/aks — AKS Cluster (Layer 2)

Manages the AKS cluster, all three node pools, workload identity federation,
ACR pull binding, and diagnostic settings. Fully destroyable as part of Layer 2.

---

## Architecture decision — Public API server (Option A)

The API server is reachable from the internet, restricted to an explicit IP
allowlist (`api_server_authorized_ip_ranges`). This allows a developer to run
`terraform apply` and `kubectl` from a laptop without a VPN, bastion, or
jumpbox, which is critical for the experimental workflow.

**Everything else is private:**

| Component | Access model |
|---|---|
| Node VMs | No public IPs; egress via UDR → Azure Firewall |
| ACR | Private Endpoint in pe-subnet |
| Key Vault | Private Endpoint in pe-subnet |
| Model storage | Private Endpoint in pe-subnet |
| Ingress | Internal load balancer (Layer 2 ingress module, not here) |

---

## Node pools

| Pool | VM SKU | Count | Purpose |
|---|---|---|---|
| `system` | Standard_D2s_v3 | 2 (fixed) | System add-ons only (`only_critical_addons_enabled`) |
| `user` | Standard_D4s_v3 | 2–5 (autoscale) | General workloads, ArgoCD, ingress |
| `gpu` | Standard_NC4as_T4_v3 | 0–2 (autoscale) | vLLM inference |

The GPU pool scales to **zero** when idle. The cluster autoscaler will provision
a node when a GPU workload pod is pending.

### GPU driver management

AKS automatically installs the NVIDIA device plugin and GPU drivers on
Standard_NC* nodes. Do **not** deploy the NVIDIA GPU Operator's driver
component — it will conflict with AKS-managed drivers. You may deploy only the
device plugin daemonset from the Operator if you need advanced features
(e.g. time-slicing), but the default AKS-managed plugin is sufficient for
single-tenant vLLM.

The T4 GPU (NC4as_T4_v3) does **not** support MIG partitioning. Do not set
`gpu_instance` on this node pool.

---

## Workload Identity — required contract

The federated identity credential (`azurerm_federated_identity_credential.vllm`)
binds the Layer 1 managed identity (`mi-qwen-vllm-dev`) to a specific
Kubernetes ServiceAccount. **Both sides of this binding must match exactly.**

### Kubernetes side (ArgoCD must create these)

```yaml
# gpu-inference namespace
apiVersion: v1
kind: Namespace
metadata:
  name: gpu-inference
  labels:
    azure.workload.identity/use: "true"
---
# vllm-sa ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vllm-sa
  namespace: gpu-inference
  annotations:
    azure.workload.identity/client-id: "<vllm_identity_client_id output>"
```

**If the namespace or ServiceAccount name differs, token exchange will fail
with a 401 from Azure AD.** The subject in the federated credential is:
`system:serviceaccount:gpu-inference:vllm-sa`

### vLLM pod side

The vLLM deployment must carry the `azure.workload.identity/use: "true"` label
and reference `vllm-sa` as its `serviceAccountName`. The Azure Workload Identity
webhook (installed by AKS automatically when `workload_identity_enabled = true`)
will inject the projected token volume and the required environment variables.

---

## Updating the API server IP allowlist

When a developer's laptop IP changes:

1. Find the new IP:
   ```bash
   curl -s https://api.ipify.org
   ```

2. Update `terraform.tfvars`:
   ```hcl
   api_server_authorized_ip_ranges = [
     "203.0.113.42/32",   # alice laptop
     "198.51.100.7/32",   # bob laptop
   ]
   ```

3. Apply the change:
   ```bash
   terraform apply -var-file="terraform.tfvars" -target='module.aks.azurerm_kubernetes_cluster.main'
   ```
   
   The `-target` flag applies only the cluster update, which takes ~30 seconds
   and does not cause node pool disruption.

---

## Kubernetes version upgrades

`automatic_upgrade_channel = "patch"` automatically applies patch releases
(e.g. 1.30.4 → 1.30.5). Minor version upgrades (1.30 → 1.31) require:

1. Update `var.kubernetes_version`
2. `terraform apply` — AKS performs a rolling upgrade across node pools

`lifecycle.ignore_changes` on `kubernetes_version` and `orchestrator_version`
prevents Terraform from reverting automatically applied patch upgrades.

---

## Calling this module from the layer2 root

```hcl
data "terraform_remote_state" "layer1" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-qwen-persistent-dev"
    storage_account_name = "stqwentfstatedev"
    container_name       = "tfstate-layer1"
    key                  = "layer1.tfstate"
    use_azuread_auth     = true
  }
}

module "aks" {
  source = "./modules/aks"

  resource_group_name        = azurerm_resource_group.ephemeral.name
  location                   = var.location
  tags                       = local.tags
  aks_subnet_id              = module.networking.aks_subnet_id
  law_workspace_id           = module.observability.workspace_id
  acr_id                     = data.terraform_remote_state.layer1.outputs.acr_id
  vllm_identity_id           = data.terraform_remote_state.layer1.outputs.vllm_identity_id
  layer1_resource_group_name = data.terraform_remote_state.layer1.outputs.resource_group_name
  tenant_id                  = var.tenant_id
  admin_group_object_ids     = var.admin_group_object_ids
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
}
```

---

## Key v4 property changes

| Old (v3) | New (v4) | Attribute |
|---|---|---|
| `enable_auto_scaling` | `auto_scaling_enabled` | node pool |
| `enable_node_public_ip` | `node_public_ip_enabled` | node pool |
| `enable_only_critical_addons` | `only_critical_addons_enabled` | default_node_pool |
| `automatic_channel_upgrade` | `automatic_upgrade_channel` | cluster |
| `log { ... }` | `enabled_log { ... }` | diagnostic setting |
| `retention_policy {}` | removed (set on workspace) | diagnostic setting |

---

## Required Azure RBAC for the operator

| Permission | Scope |
|---|---|
| Contributor | `rg-qwen-ephemeral-dev` |
| User Access Administrator | `rg-qwen-ephemeral-dev` (to create ACR pull role assignment) |
| User Access Administrator | Layer 1 RG (to create federated identity credential) |
