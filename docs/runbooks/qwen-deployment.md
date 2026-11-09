# Runbook: Qwen API Deployment

Operating guide for `qwen-api` — Qwen2.5-7B-Instruct-AWQ served via vLLM
on `aks-qwen-dev`. After the ArgoCD bootstrap, this workload is entirely
GitOps-managed from `gitops/workload-apps/qwen-api.yaml`.

---

## Prerequisites

| Requirement | How to verify |
|---|---|
| Platform layer deployed | `kubectl get applications -n argocd` shows ingress-nginx, cert-manager, KEDA as Healthy |
| Model weights uploaded | `az storage blob list --account-name stqwenmodelsdev --container-name model-weights --prefix qwen2.5-7b-instruct-awq/ \| wc -l` → 38 blobs |
| `storage.csi.accountKeySecretName` secret exists | `kubectl get secret azure-blob-csi-secret -n gpu-inference` |
| `oauth2-proxy-creds` secret exists | `kubectl get secret oauth2-proxy-creds -n oauth2-proxy` |
| Blob CSI driver enabled on cluster | `kubectl get pods -n kube-system -l app=csi-blob-node` → 1 pod per node |
| NVIDIA device plugin running | `kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds` → Running |
| GITOPS_REPO_URL replaced | `grep GITOPS_REPO_URL gitops/workload-apps/qwen-api.yaml` returns nothing |

### Manual secrets (not in GitOps — must be created once per cluster)

**Blob CSI storage account key secret:**

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

**oauth2-proxy AAD credentials secret:**
The AAD app is `qwen-aks-dev-oauth2` (client ID `<oauth2-client-id>`).

```bash
# Generate a new client secret if needed:
CLIENT_SECRET=$(az ad app credential reset \
  --id <oauth2-client-id> \
  --display-name "oauth2-proxy-k8s" \
  --query password -o tsv 2>/dev/null)

kubectl create secret generic oauth2-proxy-creds \
  --namespace oauth2-proxy \
  --from-literal=client-id=<oauth2-client-id> \
  --from-literal=client-secret="${CLIENT_SECRET}" \
  --from-literal=cookie-secret=$(openssl rand -base64 32 | head -c 32)
```

---

## Step 1 — Set the workload identity client ID

```bash
# Get the managed identity client ID from Terraform output
CLIENT_ID=$(terraform -chdir=terraform/layer1-persistent \
  output -raw vllm_identity_client_id)

echo "Client ID: ${CLIENT_ID}"

# Set it in the dev values file
sed -i "s|<set from: terraform.*>|${CLIENT_ID}|" \
  gitops/envs/dev/qwen-values.yaml
```

Commit and push this change. The client ID is not a secret.

---

## Step 2 — Replace the repo URL placeholder

If not already done during ArgoCD bootstrap:

```bash
export GITOPS_REPO_URL=https://dev.azure.com/<org>/<proj>/_git/azure-gpu-aks-ai

sed -i "s|GITOPS_REPO_URL_PLACEHOLDER|${GITOPS_REPO_URL}|g" \
  gitops/workload-apps/qwen-api.yaml

git add gitops/workload-apps/qwen-api.yaml gitops/envs/dev/qwen-values.yaml
git commit -m "chore: configure qwen-api for dev deployment"
git push
```

---

## Step 3 — ArgoCD picks up the Application

ArgoCD syncs within `timeout.reconciliation` (180 s). Force an immediate sync:

```bash
kubectl patch application qwen-api -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

Watch the sync:

```bash
kubectl get application qwen-api -n argocd -w
```

---

## Step 4 — Watch the first cold start

The first deployment provisions a GPU node from zero:

```bash
# Watch all events in order
kubectl get events -n gpu-inference --sort-by='.lastTimestamp' -w

# Watch pod lifecycle
kubectl get pods -n gpu-inference -w

# Stream vLLM startup logs once the pod is Running
kubectl logs -f -n gpu-inference \
  -l app.kubernetes.io/name=qwen-api
```

Expected log sequence:

```
INFO  Initializing an LLM engine ...
INFO  Loading model weights ...
INFO  AWQ quantization ...
INFO  Application startup complete.
INFO  Uvicorn running on http://0.0.0.0:8000
```

---

## Step 5 — Verify GPU allocation

```bash
kubectl describe pod -n gpu-inference \
  -l app.kubernetes.io/name=qwen-api \
  | grep -A5 "Limits:"
# Expected:
#   nvidia.com/gpu: 1

# Verify from the node side
GPU_NODE=$(kubectl get pods -n gpu-inference \
  -l app.kubernetes.io/name=qwen-api \
  -o jsonpath='{.items[0].spec.nodeName}')
kubectl describe node "${GPU_NODE}" | grep -A10 "Allocated resources"
```

---

## Step 6 — Test the API

```bash
# Port-forward (bypasses oauth2-proxy; dev only)
kubectl port-forward svc/qwen-api 8080:8000 -n gpu-inference &

# Health
curl -s http://localhost:8080/health

# Available models
curl -s http://localhost:8080/v1/models | jq '.data[].id'
# Expected: "qwen"

# Chat completion
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen",
    "messages": [{"role": "user", "content": "What is 2 + 2?"}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '.choices[0].message.content'

# Stop port-forward
kill %1
```

---

## Accessing via the internal ingress

The ingress LB is internal (private IP 10.1.1.100 on aks-subnet).
Access it from a host on the same VNet (e.g. via Azure Bastion) or by
adding the static IP to `/etc/hosts` from a laptop connected via VPN.

```bash
# Get the internal LB IP
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Expected: 10.1.1.100

# Add to /etc/hosts (macOS/Linux)
echo "10.1.1.100 qwen.dev.internal" | sudo tee -a /etc/hosts

# Test (requires VPN or Bastion)
curl -sk https://qwen.dev.internal/health
```

---

## Scaling

### Manual scale-up

```bash
kubectl scale deployment/qwen-api -n gpu-inference --replicas=1
```

### Adjust KEDA parameters

Edit `gitops/envs/dev/qwen-values.yaml`:

```yaml
keda:
  minReplicaCount: 1    # keep GPU node warm (increases cost)
  cooldownPeriod: 300   # scale down faster
```

Commit and push; ArgoCD applies within 180 s.

### Disable KEDA (fixed replica)

```yaml
keda:
  enabled: false
replicaCount: 1
```

---

## Updating the model or vLLM version

1. Edit `gitops/charts/qwen-api/values.yaml`:
   - `image.tag`: new vLLM version
   - `model.name`: new model ID
   - `Chart.yaml` `appVersion`: match new vLLM version
2. If model weights changed, upload new weights (Prompt 9 script) first.
3. Commit and push. ArgoCD triggers a Deployment rollout.
4. The Deployment uses `strategy: Recreate` — the old pod is deleted before
   the new one starts (prevents 2× GPU allocation on a single node).

---

## Emergency: force a pod restart

```bash
kubectl rollout restart deployment/qwen-api -n gpu-inference
kubectl rollout status deployment/qwen-api -n gpu-inference
```

## Scale to zero manually (cost saving)

```bash
kubectl scale deployment/qwen-api -n gpu-inference --replicas=0
# AKS will eventually reclaim the GPU node after scale-down TTL
```
