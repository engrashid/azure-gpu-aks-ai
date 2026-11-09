# Runbook: vLLM Troubleshooting

Diagnostic guide for `qwen-api` failures on `aks-qwen-dev`.

---

## Quick diagnostic checklist

```bash
# 1. Application and pod state
kubectl get application qwen-api -n argocd
kubectl get pods -n gpu-inference -o wide
kubectl get events -n gpu-inference --sort-by='.lastTimestamp' | tail -30

# 2. PVC / Blob CSI state
kubectl get pvc -n gpu-inference
kubectl describe pvc qwen-api-models -n gpu-inference

# 3. GPU node state
kubectl get nodes -l gpu-type=nvidia-t4
kubectl describe node <gpu-node> | grep -E "Taints:|Conditions:|Allocatable:" -A5

# 4. NVIDIA device plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
kubectl get node -l accelerator=nvidia -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'

# 5. Blob CSI driver
kubectl get pods -n kube-system -l app=csi-blob-node

# 6. Recent logs
kubectl logs -n gpu-inference \
  -l app.kubernetes.io/name=qwen-api \
  --previous 2>/dev/null || \
kubectl logs -n gpu-inference \
  -l app.kubernetes.io/name=qwen-api
```

---

## Symptom: Pod stuck in Pending

### Cause 1 — No GPU node available

```
0/N nodes are available: N Insufficient nvidia.com/gpu
```

**Diagnose:**
```bash
kubectl get nodes -l gpu-type=nvidia-t4
kubectl describe pod -n gpu-inference <pod-name> | grep -A5 Events
```

**Fix:** Wait 5–10 minutes for AKS to provision the GPU node. If it never comes up:
```bash
kubectl logs -n kube-system -l app=cluster-autoscaler | tail -50
az vm list-usage --location eastus --query "[?name.value=='standardNCASv3Family']"
```

### Cause 2 — NVIDIA device plugin not running

```
0/N nodes are available: 1 Insufficient nvidia.com/gpu
```
Even though a GPU node exists, `nvidia.com/gpu` is missing from `kubectl describe node`.

**Root cause:** `gpu_driver = "Install"` in Terraform installs the NVIDIA driver on the
node OS, but does NOT deploy the NVIDIA Kubernetes Device Plugin DaemonSet. Without it,
Kubernetes cannot see the GPU resource.

**Diagnose:**
```bash
kubectl get daemonset -n kube-system | grep nvidia
kubectl describe node <gpu-node> | grep "nvidia.com/gpu"
# Missing = device plugin not running
```

**Fix:** The device plugin is GitOps-managed via `gitops/platform-apps/nvidia-device-plugin.yaml`.
On a fresh cluster, force an ArgoCD sync of `platform-root` and then `nvidia-device-plugin`.
If you need to apply it manually in an emergency:
```bash
kubectl apply -f gitops/platform-apps/nvidia-device-plugin.yaml
# Then sync via ArgoCD
argocd app sync nvidia-device-plugin
```

Verify after deployment:
```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
kubectl describe node <gpu-node> | grep "nvidia.com/gpu"
# Expected: nvidia.com/gpu: 1
```

**Note:** The NVIDIA device plugin image is hosted on `nvcr.io`. The Azure Firewall must
have `nvcr.io` and `*.nvcr.io` in the NVIDIA allow rule — this is configured in
`terraform/layer2-ephemeral/modules/networking/firewall-rules.tf`.

### Cause 3 — Node selector mismatch

```
0/N nodes are available: N node(s) didn't match node selector
```

**Fix:** Verify GPU node labels match `values.gpu.nodeSelector`:
```bash
kubectl get nodes --show-labels | grep gpu
# Expected labels: gpu-type=nvidia-t4, workload=llm, role=gpu
```

### Cause 4 — Toleration missing

```
0/N nodes are available: N node(s) had untolerated taint: nvidia.com/gpu=present:NoSchedule
```

**Fix:** Ensure `gpu.tolerations` in values.yaml includes the GPU taint:
```yaml
gpu:
  tolerations:
    - key: nvidia.com/gpu
      operator: Equal
      value: "present"
      effect: NoSchedule
```

---

## Symptom: Pod stuck in ContainerCreating

### Cause 1 — Blob CSI driver not enabled on cluster

```
MountVolume.MountDevice failed: driver name blob.csi.azure.com not found in the list of registered CSI drivers
```

**Root cause:** AKS does not enable the Azure Blob CSI driver by default. It must be
explicitly enabled on the cluster.

**Diagnose:**
```bash
kubectl get pods -n kube-system -l app=csi-blob-node
# Empty = blob CSI driver not enabled
```

**Fix (one-time):**
```bash
az aks update \
  --resource-group rg-qwen-ephemeral-dev \
  --name aks-qwen-dev \
  --enable-blob-driver \
  --yes
```

Wait ~2 minutes for `csi-blob-node` DaemonSet pods to appear on all nodes.
This is also configured in Terraform (`storage_profile { blob_driver_enabled = true }`).

### Cause 2 — Blob CSI mount: `listKeys` 403 Forbidden

```
MountVolume.SetUp failed: failed to list keys, error: POST .../listKeys
RESPONSE 403: 403 Forbidden — AuthorizationFailed
```

**Root cause:** The blob CSI driver defaults to calling `listKeys` on the storage account
management plane to retrieve an account key for blobfuse2. When `clientID` is set in the
PV `volumeAttributes`, the driver uses that managed identity to call `listKeys` — but the
vLLM identity only has `Storage Blob Data Reader` (data plane only), not the management
plane `listKeys` action.

**Important:** Setting `nodeStageSecretRef` in the PV does NOT fix this if `clientID` is
also present in `volumeAttributes`. The driver checks `clientID` first and calls `listKeys`
regardless of `nodeStageSecretRef`.

**Fix:** Use an explicit Kubernetes secret containing the storage account key. The PV must
have `nodeStageSecretRef` set AND `clientID` must be absent from `volumeAttributes`.

Create the secret (once per cluster):
```bash
STORAGE_KEY=$(az storage account keys list \
  --resource-group rg-qwen-persistent-dev \
  --account-name stqwenmodelsdev \
  --query '[0].value' -o tsv 2>/dev/null)

kubectl create secret generic azure-blob-csi-secret \
  --namespace gpu-inference \
  --from-literal=azurestorageaccountname=stqwenmodelsdev \
  --from-literal=azurestorageaccountkey="${STORAGE_KEY}"
```

This secret is referenced via `storage.csi.accountKeySecretName: azure-blob-csi-secret`
in `gitops/envs/dev/qwen-values.yaml`. The chart template conditionally excludes `clientID`
from `volumeAttributes` when this value is set.

### Cause 3 — Image pull failure: Docker Hub CDN blocked

```
Failed to pull image "vllm/vllm-openai:v0.6.4": failed to copy: Get
"https://production.cloudflare.docker.com/...": EOF
```

**Root cause:** Docker Hub serves large image layer blobs via `production.cloudflare.docker.com`.
The Azure Firewall blocks this CDN by default.

**Fix:** The firewall rule `allow-dockerhub-blob-cdn` in
`terraform/layer2-ephemeral/modules/networking/firewall-rules.tf` must include
`production.cloudflare.docker.com`. Apply with:
```bash
cd terraform/layer2-ephemeral
terraform apply -target=module.networking -auto-approve
```

---

## Symptom: Pod in CrashLoopBackOff

### Cause 1 — vLLM trying to contact HuggingFace Hub

```
huggingface_hub.errors.OfflineModeIsEnabled: Cannot reach
https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-AWQ/resolve/main/config.json:
offline mode is enabled.
```

**Root cause:** When `--model` is a HuggingFace Hub ID (e.g. `Qwen/Qwen2.5-7B-Instruct-AWQ`),
vLLM checks HuggingFace Hub for `config.json` even when `TRANSFORMERS_OFFLINE=1` is set.
This is a first-pass Hub connectivity check that precedes any local cache lookup.

Our model is uploaded flat to the blob container (not in HF cache format), so the Hub ID
approach cannot work offline regardless.

**Fix:** Pass the local blob mount path directly as `--model`:
```
--model=/mnt/models/qwen2.5-7b-instruct-awq
```
When a local filesystem path is passed, vLLM skips all Hub interactions and reads
`config.json` directly from disk. This is how the chart is now configured.

Verify the current pod args:
```bash
kubectl get pod -n gpu-inference <pod-name> \
  -o jsonpath='{.spec.containers[0].args}' | python3 -m json.tool
# --model should be a /mnt/... path, not a Qwen/... Hub ID
```

### Cause 2 — Model weights missing or wrong path

```
OSError: [Errno 2] No such file or directory: '/mnt/models/qwen2.5-7b-instruct-awq'
```

**Diagnose:**
```bash
# Verify blobs exist in the container
az storage blob list \
  --account-name stqwenmodelsdev \
  --container-name model-weights \
  --prefix qwen2.5-7b-instruct-awq/ \
  --output table | head -10

# Check mount inside pod
kubectl exec -n gpu-inference <pod-name> -- ls /mnt/models/qwen2.5-7b-instruct-awq/
# Expected: config.json, *.safetensors, tokenizer.json, etc.
```

**Fix:** If blobs are missing, re-run the upload script:
```bash
bash scripts/upload-model.sh
```

### Cause 3 — Out of GPU memory (OOM)

```
torch.cuda.OutOfMemoryError: CUDA out of memory
```

**Fix:**
```yaml
# gitops/envs/dev/qwen-values.yaml
model:
  gpuMemoryUtilization: 0.85
  maxModelLen: 4096
```

---

## Symptom: Pod Running but API returning errors

### 503 Service Unavailable

Pod is running but readiness probe hasn't passed (model still loading).
```bash
kubectl get pod -n gpu-inference <pod-name> \
  -o jsonpath='{.status.containerStatuses[0].ready}'
# false = still loading; wait for true (can take 2–3 min)
```

### 401 Unauthorized from ingress

oauth2-proxy is failing. Most common cause: `oauth2-proxy-creds` secret missing.

```bash
kubectl get secret -n oauth2-proxy oauth2-proxy-creds
kubectl get pods -n oauth2-proxy
kubectl logs -n oauth2-proxy -l app.kubernetes.io/name=oauth2-proxy | tail -20
```

**Fix:** Create the secret (see `docs/runbooks/oauth2-proxy-aad-setup.md`):
```bash
kubectl create secret generic oauth2-proxy-creds \
  -n oauth2-proxy \
  --from-literal=client-id=<AAD_APP_CLIENT_ID> \
  --from-literal=client-secret=<AAD_APP_CLIENT_SECRET> \
  --from-literal=cookie-secret=$(openssl rand -base64 32 | head -c 32)
kubectl rollout restart deployment/oauth2-proxy -n oauth2-proxy
```

For `aks-qwen-dev`, the AAD app is `qwen-aks-dev-oauth2`
(client ID `<oauth2-client-id>`). Retrieve a new client secret via:
```bash
az ad app credential reset \
  --id <oauth2-client-id> \
  --display-name "oauth2-proxy-k8s" \
  --query password -o tsv 2>/dev/null
```

### 504 Gateway Timeout on long completions

**Fix:** Verify ingress has 600s timeouts:
```bash
kubectl get ingress qwen-api -n gpu-inference -o yaml | grep timeout
# Expected: proxy-read-timeout: "600", proxy-send-timeout: "600"
```

---

## Symptom: KEDA not scaling

```bash
kubectl get scaledobject qwen-api -n gpu-inference
kubectl describe scaledobject qwen-api -n gpu-inference
```

| Issue | Fix |
|---|---|
| KEDA pods not running | `kubectl get pods -n keda` |
| `minReplicaCount: 0` with CPU trigger | KEDA rejects this — CPU metrics unavailable at 0 pods. Set `minReplicaCount: 1` or switch to HTTP/Prometheus trigger |
| ScaledObject status `False` | `kubectl logs -n keda -l app=keda-operator` |

---

## Symptom: ArgoCD qwen-api OutOfSync / SyncFailed

### PV immutability error

```
PersistentVolume "qwen-api-models-pv" is invalid:
spec.persistentvolumesource: Forbidden: spec.persistentvolumesource is immutable after creation
```

**Fix:** Delete the PV and PVC so ArgoCD can recreate them from the updated template:
```bash
# Remove finalizers first to allow immediate deletion
kubectl patch pvc qwen-api-models -n gpu-inference -p '{"metadata":{"finalizers":null}}'
kubectl delete pvc qwen-api-models -n gpu-inference
kubectl patch pv qwen-api-models-pv -p '{"metadata":{"finalizers":null}}'
kubectl delete pv qwen-api-models-pv
# Then re-sync
kubectl patch application qwen-api -n argocd --type merge -p '{"operation": null}'
argocd app sync qwen-api
```

### `--force cannot be used with --server-side`

Do not pass `--force` to `argocd app sync` when the app has `ServerSideApply=true` in
its sync options. Use plain `argocd app sync <app>` instead.

---

## Symptom: Very slow first-token latency

Expected on T4 (NC4as_T4_v3) with AWQ 4-bit:
- Time-to-first-token: 2–5 s for 1K-token prompt
- Generation speed: 30–60 tokens/s

**Tuning:**
```yaml
model:
  gpuMemoryUtilization: 0.92
extraEnv:
  PYTORCH_CUDA_ALLOC_CONF: "max_split_size_mb:256"
```

---

## Collecting a full diagnostic bundle

```bash
#!/usr/bin/env bash
NS=gpu-inference
OUT_DIR="vllm-diag-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT_DIR}"

kubectl get all -n "${NS}" -o yaml                        > "${OUT_DIR}/all-resources.yaml"
kubectl get events -n "${NS}"                             > "${OUT_DIR}/events.txt"
kubectl describe pvc -n "${NS}"                           > "${OUT_DIR}/pvc.txt"
kubectl get pv qwen-api-models-pv -o yaml                 > "${OUT_DIR}/pv.yaml" 2>/dev/null || true
kubectl get application qwen-api -n argocd -o yaml        > "${OUT_DIR}/argocd-app.yaml"
kubectl describe scaledobject qwen-api -n "${NS}"         > "${OUT_DIR}/scaledobject.txt" 2>/dev/null || true
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds > "${OUT_DIR}/nvidia-dp.txt"
kubectl get pods -n kube-system -l app=csi-blob-node      > "${OUT_DIR}/blob-csi.txt"

POD=$(kubectl get pod -n "${NS}" -l app.kubernetes.io/name=qwen-api \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "${POD}" ]]; then
  kubectl logs "${POD}" -n "${NS}"                        > "${OUT_DIR}/vllm.log" 2>&1
  kubectl describe pod "${POD}" -n "${NS}"                > "${OUT_DIR}/pod.txt"
  kubectl get pod "${POD}" -n "${NS}" -o json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); \
      print(json.dumps(d['spec']['containers'][0].get('args',[]), indent=2))" \
    > "${OUT_DIR}/vllm-args.json"
fi

GPU_NODE=$(kubectl get nodes -l accelerator=nvidia -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${GPU_NODE}" ]]; then
  kubectl describe node "${GPU_NODE}"                     > "${OUT_DIR}/gpu-node.txt"
fi

tar czf "${OUT_DIR}.tar.gz" "${OUT_DIR}/"
echo "Bundle: ${OUT_DIR}.tar.gz"
```
