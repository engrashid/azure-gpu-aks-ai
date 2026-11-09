# Runbook: GPU Stack Bootstrap

Documents the complete bootstrap sequence for the GPU inference stack on `aks-qwen-dev`,
including known issues discovered during initial deployment and their fixes.

---

## Architecture overview

```
Internet → Azure Firewall (FQDN rules) → AKS Spoke VNet
                                             │
                                    ┌────────┴────────┐
                                    │   GPU Node Pool  │
                                    │  NC4as_T4_v3     │
                                    │                  │
                               NVIDIA Device Plugin    │
                               (DaemonSet, kube-system)│
                                    │                  │
                               qwen-api Pod            │
                               ├── vLLM server         │
                               ├── nvidia.com/gpu: 1   │
                               └── Blob CSI mount      │
                                    └── stqwenmodelsdev │
                                        model-weights/ │
```

---

## Bootstrap order

```
1. terraform apply (layer1)       → storage account, ACR, Key Vault, managed identities
2. bash scripts/upload-model.sh   → upload Qwen2.5-7B-Instruct-AWQ weights to blob
3. terraform apply (layer2)       → AKS cluster, networking, firewall, ArgoCD
4. bash scripts/import-argocd-state.sh → import existing ArgoCD resources into TF state
5. kubectl: create manual secrets → azure-blob-csi-secret, oauth2-proxy-creds
6. ArgoCD sync                    → deploys all platform + workload apps
```

---

## Known issues and fixes (from initial deployment 2026-04-19)

### Issue 1 — NVIDIA device plugin not deployed after GPU node provisioned

**Symptom:**

```
0/4 nodes are available: 1 Insufficient nvidia.com/gpu
```

GPU node is Ready and labelled correctly, but `nvidia.com/gpu` is absent from
`kubectl describe node` Allocatable section.

**Root cause:** Terraform `gpu_driver = "Install"` provisions the NVIDIA GPU driver on the
OS. It does NOT deploy the NVIDIA Kubernetes Device Plugin DaemonSet. Without the device
plugin, Kubernetes has no knowledge of the GPU resource and cannot schedule pods requesting
`nvidia.com/gpu`.

**Fix:** Added `gitops/platform-apps/nvidia-device-plugin.yaml` — an ArgoCD Application
that deploys the official NVIDIA device plugin Helm chart (`nvidia.github.io/k8s-device-plugin`)
into `kube-system` with the correct toleration for the `nvidia.com/gpu=present:NoSchedule`
taint and `nodeSelector: accelerator: nvidia`.

Also required: adding `nvcr.io` and `*.nvcr.io` to the Azure Firewall NVIDIA FQDN allow
rule — the device plugin image is only published on NVIDIA Container Registry.

---

### Issue 2 — Azure Blob CSI driver not enabled on AKS cluster

**Symptom:**

```
MountVolume.MountDevice failed: driver name blob.csi.azure.com not found
in the list of registered CSI drivers
```

**Root cause:** AKS does not enable the Azure Blob CSI driver by default. The Terraform
`azurerm_kubernetes_cluster` resource requires an explicit `storage_profile { blob_driver_enabled = true }`
block. Without it, the `blob.csi.azure.com` driver is unavailable on nodes.

**Fix:**

```bash
az aks update \
  --resource-group rg-qwen-ephemeral-dev \
  --name aks-qwen-dev \
  --enable-blob-driver \
  --yes
```

Also added `storage_profile { blob_driver_enabled = true }` to the AKS Terraform module.

---

### Issue 3 — Blob CSI `clientID` in volumeAttributes overrides `nodeStageSecretRef`

**Symptom:**

```
MountVolume.SetUp failed: failed to list keys, error: POST
.../storageAccounts/stqwenmodelsdev/listKeys
RESPONSE 403: 403 Forbidden — AuthorizationFailed
The client '<vllm-identity-client-id>' does not have authorization to perform action
'Microsoft.Storage/storageAccounts/listKeys/action'
```

**Root cause:** The Azure Blob CSI driver's auth priority:

1. If `clientID` is set in `spec.csi.volumeAttributes`, the driver uses that managed
   identity to call `listKeys` on the storage management plane (to obtain the account key
   for blobfuse2).
2. `nodeStageSecretRef` is ignored if `clientID` is present.

The vLLM managed identity only has `Storage Blob Data Reader` (data plane), not the
`listKeys` management plane action.

**Fix:** Two-part:

1. Create a Kubernetes secret with the storage account key:

```bash
kubectl create secret generic azure-blob-csi-secret \
  --namespace gpu-inference \
  --from-literal=azurestorageaccountname=stqwenmodelsdev \
  --from-literal=azurestorageaccountkey="$(az storage account keys list \
    --resource-group rg-qwen-persistent-dev \
    --account-name stqwenmodelsdev \
    --query '[0].value' -o tsv 2>/dev/null)"
```

1. Updated `gitops/charts/qwen-api/templates/persistentvolume.yaml` to:
   - Add `nodeStageSecretRef` when `storage.csi.accountKeySecretName` is set
   - Conditionally **omit** `clientID` from `volumeAttributes` when using the secret
     (having both causes the driver to use `clientID` for `listKeys`, ignoring the secret)

Relevant chart logic:

```yaml
volumeAttributes:
  {{- if not .Values.storage.csi.accountKeySecretName }}
  clientID: {{ .Values.storage.csi.clientID | quote }}
  {{- end }}
  protocol: fuse2
{{- if .Values.storage.csi.accountKeySecretName }}
nodeStageSecretRef:
  name: {{ .Values.storage.csi.accountKeySecretName }}
  namespace: {{ .Release.Namespace }}
{{- end }}
```

---

### Issue 4 — vLLM crashes at startup: HuggingFace Hub check fails offline

**Symptom:**

```
huggingface_hub.errors.OfflineModeIsEnabled: Cannot reach
https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-AWQ/resolve/main/config.json:
offline mode is enabled.
```

**Root cause:** When `--model` is a HuggingFace Hub model ID, vLLM makes an HTTPS request
to Hub to resolve `config.json` even before checking the local `--download-dir`. With
`TRANSFORMERS_OFFLINE=1` set, this check is blocked and vLLM exits immediately.

Additionally, our upload script stores model weights flat in the blob container:

```
model-weights/qwen2.5-7b-instruct-awq/config.json
model-weights/qwen2.5-7b-instruct-awq/model-*.safetensors
...
```

This is NOT the HuggingFace cache directory format (`models--Qwen--Qwen2.5-7B-Instruct-AWQ/snapshots/<hash>/...`),
so the Hub ID approach would fail even if Hub were reachable.

**Fix:** Changed `--model` arg in `gitops/charts/qwen-api/templates/deployment.yaml` from
the Hub model ID to the local blob mount path:

```
Before: --model=Qwen/Qwen2.5-7B-Instruct-AWQ --download-dir=/mnt/models/qwen2.5-7b-instruct-awq
After:  --model=/mnt/models/qwen2.5-7b-instruct-awq
```

When a local path is passed, vLLM reads `config.json` directly from disk with no Hub
connectivity required.

---

### Issue 5 — Docker Hub large layer downloads blocked by firewall

**Symptom:**

```
Failed to pull image "vllm/vllm-openai:v0.6.4": failed to copy:
Get "https://production.cloudflare.docker.com/registry-v2/...": EOF
```

**Root cause:** Docker Hub routes large image layer downloads through
`production.cloudflare.docker.com` CDN. The Azure Firewall had rules for
`*.docker.io` and `*.r2.cloudflarestorage.com` but was missing this Cloudflare CDN.

**Fix:** Added `production.cloudflare.docker.com` to the `allow-dockerhub-blob-cdn`
rule in `terraform/layer2-ephemeral/modules/networking/firewall-rules.tf`.

---

### Issue 6 — oauth2-proxy pod in `CreateContainerConfigError`

**Symptom:**

```
Error: secret "oauth2-proxy-creds" not found
```

**Root cause:** By design, oauth2-proxy credentials (AAD client ID, client secret,
cookie secret) are not committed to git. The secret must be created manually once per
cluster before the pod can start.

**Fix:** Create the secret (see Prerequisites section in `qwen-deployment.md`).
The AAD app `qwen-aks-dev-oauth2` was created for this cluster with:

- Client ID: `<oauth2-client-id>`
- Redirect URI: `https://qwen.dev.internal/oauth2/callback`
- Graph permissions: `openid`, `email`, `profile`
- Tenant: `<tenant-id>`

---

### Issue 7 — AKS control-plane identity missing Network Contributor on spoke VNet

**Symptom:** `ingress-nginx` LoadBalancer service stuck at `<pending>` for hours.

**Root cause:** AKS cloud-controller-manager needs `Network Contributor` on the spoke
VNet to provision internal load balancers. This assignment was missing.

**Fix:** Added to `terraform/layer2-ephemeral/modules/aks/rbac.tf`:

```hcl
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.spoke_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}
```

---

### Issue 8 — ArgoCD perpetual OutOfSync on ValidatingWebhookConfiguration

**Symptom:** cert-manager and KEDA apps permanently OutOfSync despite no changes.

**Root cause:** AKS injects two `matchExpressions` into every
`ValidatingWebhookConfiguration`'s `namespaceSelector` at the cluster level:

- `kubernetes.azure.com/managedby NotIn aks`
- `control-plane NotIn true`

ArgoCD detects this as drift because these expressions are not in the Helm chart manifests.

**Fix:**

1. Added `RespectIgnoreDifferences=true` to `syncOptions` in both `cert-manager.yaml`
   and `keda.yaml` ArgoCD Applications (without this, ArgoCD still marks them OutOfSync
   even if it suppresses the UI diff).
2. Added per-app `ignoreDifferences` for the VWC resource using `jqPathExpressions`
   targeting `.webhooks[].namespaceSelector.matchExpressions`.
3. Added global ArgoCD CM customizations in `argocd-install-values.yaml` for both
   `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration`.

---

## Firewall rules added during initial deployment

The following FQDN rules were added beyond the initial Terraform plan:

| Rule | Domain(s) added | Reason |
|---|---|---|
| `allow-nvidia` | `nvcr.io`, `*.nvcr.io` | NVIDIA device plugin image |
| `allow-dockerhub-blob-cdn` | `production.cloudflare.docker.com` | Docker Hub layer CDN |
| `allow-github` | `*.github.io`, `ghcr.io`, `pkg.github.com` | KEDA images + Helm repo |
| `allow-kubernetes-registries` | `*.pkg.dev`, `*.amazonaws.com` | registry.k8s.io blob CDNs |
| `allow-helm` | `charts.jetstack.io` | cert-manager Helm repo |

All are committed to `terraform/layer2-ephemeral/modules/networking/firewall-rules.tf`.

---

## Verifying a healthy cluster

```bash
# All platform apps Synced + Healthy
kubectl get applications -n argocd

# GPU node has nvidia.com/gpu allocatable
kubectl get node -l accelerator=nvidia \
  -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
# Expected: 1

# vLLM is responding
POD=$(kubectl get pods -n gpu-inference -l app.kubernetes.io/name=qwen-api \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n gpu-inference "${POD}" -- \
  curl -s http://localhost:8000/v1/models | python3 -m json.tool
# Expected: model id "qwen"

# Send a test completion
kubectl exec -n gpu-inference "${POD}" -- \
  curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen","messages":[{"role":"user","content":"Say hello."}],"max_tokens":20}' \
  | python3 -m json.tool
```
