# Runbook: ArgoCD Bootstrap

One-time procedure to install ArgoCD and activate GitOps on `aks-qwen-dev`.
After this runbook completes, all cluster changes are made by pushing to `main`.

---

## Prerequisites

| Requirement | How to verify |
|---|---|
| kubectl context = aks-qwen-dev | `kubectl config current-context` |
| API server reachable | `kubectl cluster-info` |
| kubelogin configured | `kubelogin convert-kubeconfig -l azurecli` |
| Namespaces exist | `kubectl get ns argocd platform gpu-inference` |
| Helm ≥ 3.14 | `helm version` |
| Azure DevOps / GitHub PAT | Token with `Code (Read)` scope on this repo |

### Set required environment variables

```bash
# Personal Access Token with read access to the gitops repo
export AZDO_PAT=<your-pat>

# Full HTTPS URL of the git repo ArgoCD will clone
export GITOPS_REPO_URL=https://dev.azure.com/<org>/<proj>/_git/azure-gpu-aks-ai
```

### Verify namespaces (created by validate-and-test.sh)

```bash
kubectl get ns argocd platform gpu-inference
# All three must show STATUS=Active before proceeding.
```

---

## Running the bootstrap script

```bash
cd /path/to/azure-gpu-aks-ai

bash scripts/bootstrap-argocd.sh
```

### With optional overrides

```bash
# Override the chart version
bash scripts/bootstrap-argocd.sh --argocd-version 9.5.2

# Override the repo URL inline instead of via env var
bash scripts/bootstrap-argocd.sh --gitops-repo-url https://github.com/<org>/azure-gpu-aks-ai

# Skip Helm install (re-apply projects + root-app only)
bash scripts/bootstrap-argocd.sh --skip-install
```

Expected run time: **~5–8 minutes** (Helm install ~3 min, pod startup ~2 min).

---

## Accessing the ArgoCD UI

ArgoCD is deployed with `ClusterIP` only (no public LoadBalancer). Access it
via port-forward from your laptop:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Then open: **http://localhost:8080**

Keep this terminal open while using the UI. Port-forward terminates when
you close the terminal.

---

## Logging in

| Field | Value |
|---|---|
| Username | `admin` |
| Password | Contents of `argocd-admin-password.txt` in repo root |

```bash
# Print the password
cat argocd-admin-password.txt

# Or copy it to clipboard (macOS)
cat argocd-admin-password.txt | pbcopy
```

> **Security note:** `argocd-admin-password.txt` is in `.gitignore`.
> Never commit it. The file is `chmod 600` (owner read-only).

---

## Watching sync status

```bash
# List all Applications and their sync/health status
kubectl get applications -n argocd

# Live watch (refreshes every few seconds)
kubectl get applications -n argocd -w

# Detailed view of a specific application
kubectl describe application platform-root -n argocd
kubectl describe application workloads-root -n argocd
```

Expected initial state after bootstrap:
- `platform-root`: **Synced / Healthy** (or **Synced / Suspended** if
  `gitops/platform-apps/` is empty — this is normal)
- `workloads-root`: **Synced / Healthy** (or **Synced / Suspended** if
  `gitops/workload-apps/` is empty)

---

## Forcing a manual sync

ArgoCD syncs automatically every 180 s. To trigger an immediate sync:

```bash
# Via kubectl patch
kubectl patch application platform-root -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

kubectl patch application workloads-root -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

Or use the ArgoCD CLI (if installed):

```bash
argocd login localhost:8080 --username admin --password "$(cat argocd-admin-password.txt)" --insecure
argocd app sync platform-root
argocd app sync workloads-root
```

---

## Common failures and fixes

### PAT expired → ArgoCD cannot clone the repo

**Symptom:** Applications stuck `OutOfSync`, repo-server logs show
`authentication required` or `403 Forbidden`.

**Fix:**
```bash
# Generate a new PAT in Azure DevOps / GitHub
export AZDO_PAT=<new-pat>

# Recreate the credential secret
kubectl delete secret argocd-repo-gitops -n argocd
kubectl create secret generic argocd-repo-gitops \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="${GITOPS_REPO_URL}" \
  --from-literal=username=argocd \
  --from-literal=password="${AZDO_PAT}"
kubectl label secret argocd-repo-gitops -n argocd \
  "argocd.argoproj.io/secret-type=repository" \
  "managed-by=bootstrap-script" \
  --overwrite
```

ArgoCD re-reads credentials automatically within ~30 s.

---

### Namespace already exists conflict on re-run

**Symptom:** Script fails with `Error from server (AlreadyExists): namespaces "argocd" already exists`.

**Fix:** Use `--skip-install` to bypass the Helm install and re-apply only
the projects and root-app:

```bash
bash scripts/bootstrap-argocd.sh --skip-install
```

---

### Root-app OutOfSync forever

**Symptom:** `platform-root` or `workloads-root` shows `OutOfSync` for more
than 5 minutes and does not self-heal.

**Diagnose:**

```bash
kubectl describe application platform-root -n argocd
# Look for: "ComparisonError", "rpc error", "repository not found"
```

**Common causes and fixes:**

| Cause | Fix |
|---|---|
| Wrong repo URL in Application | Delete and re-apply root-app with correct `GITOPS_REPO_URL` |
| Wrong branch (`main` does not exist) | Push an initial commit to `main` or change `targetRevision` |
| Wrong path (`gitops/platform-apps` does not exist) | Create the directory and push a `.gitkeep` |
| PAT invalid | See "PAT expired" section above |
| ArgoCD cannot reach Azure DevOps (firewall) | Check Firewall application rules allow `dev.azure.com` |

**Re-apply root-app after fix:**

```bash
export GITOPS_REPO_URL=<corrected-url>
sed "s|GITOPS_REPO_URL_PLACEHOLDER|${GITOPS_REPO_URL}|g" \
  gitops/bootstrap/root-app.yaml | kubectl apply -f -
```

---

### ArgoCD pods not Ready after install

**Symptom:** `kubectl rollout status` times out.

**Diagnose:**

```bash
kubectl get pods -n argocd
kubectl describe pod <failing-pod> -n argocd
kubectl logs <failing-pod> -n argocd
```

**Common causes:**

- Insufficient CPU/memory on system node pool → check node conditions:
  `kubectl describe node <system-node>`
- Image pull failure → check ACR private endpoint DNS resolution:
  `kubectl run dns-test --image=busybox --restart=Never -it --rm -- nslookup acrqwendev.azurecr.io`

---

### Redis ImagePullBackOff (ArgoCD 9.x)

**Symptom:** `argocd-redis` pod stuck in `ImagePullBackOff`. Event shows:

```
Failed to pull image "ecr-public.aws.com/docker/library/redis:8.2.3-alpine": EOF
```

**Root cause:** ArgoCD 9.x changed the Redis image source from `docker.io` to
`ecr-public.aws.com`. Image layer blobs are served via AWS CloudFront
(`*.cloudfront.net`). Docker Hub blobs are served via Cloudflare R2
(`*.r2.cloudflarestorage.com`). Both CDN domains must be explicitly allowed in
the Azure Firewall application rules.

`argocd-install-values.yaml` already overrides the Redis image back to `docker.io`
to avoid ECR Public. If you see this error anyway, verify the Helm values file
is being picked up, and that `*.r2.cloudflarestorage.com` is in the firewall rules.

**Firewall rules required** (in `terraform/layer2-ephemeral/modules/networking/firewall-rules.tf`):

```hcl
rule {
  name              = "allow-dockerhub-blob-cdn"
  destination_fqdns = ["*.r2.cloudflarestorage.com"]
  ...
}
rule {
  name              = "allow-ecr-public-blob-cdn"
  destination_fqdns = ["*.cloudfront.net"]
  ...
}
```

---

### All ArgoCD pods: persistent EOF on API server calls

**Symptom:** Every pod logs:

```
failed to list *v1.Secret: Get "https://172.16.0.1:443/...": EOF
```

`argocd-server` crashes with exit code 143 (liveness probe kill). Other pods
show `1/1 Running` but their informers never sync.

**Root cause:** The cluster uses Azure CNI Overlay (pod CIDR `172.17.0.0/16`,
service CIDR `172.16.0.0/16`). When pods access the Kubernetes API via the
service ClusterIP `172.16.0.1:443`, iptables DNATs the traffic to the public
API server IP. The Go TLS client sends **no SNI** for IP-based URLs. Azure
Firewall's FQDN application rule (`*.hcp.eastus.azmk8s.io:443`) requires SNI
to match — without SNI the rule is skipped and the connection is denied (EOF).

**Fix:** A network rule (not application rule) for TCP 443 to `AzureCloud` is
required alongside the existing 9000/1194 tunnel rule. This is already present
in `firewall-rules.tf`:

```hcl
rule {
  name                  = "allow-aks-api-tunnel"
  destination_ports     = ["443", "9000", "1194"]   # 443 is critical
  destination_addresses = ["AzureCloud.${var.location}"]
  protocols             = ["TCP", "UDP"]
}
```

If you recreate the firewall or networking module and this rule is missing,
**all in-cluster controllers will fail** (ArgoCD, KEDA, cert-manager, etc.).
Run `terraform apply -target='module.networking.azurerm_firewall_policy_rule_collection_group.workload'`
to restore it without touching other resources.

---

### argocd-redis pod: CreateContainerConfigError — secret "argocd-redis" not found

**Symptom:** Redis pod shows `CreateContainerConfigError`. Describe shows:
`Error: secret "argocd-redis" not found`

**Root cause:** `argocd-install-values.yaml` sets `redisSecretInit.enabled: false`
to skip the pre-install hook Job. That Job's only job is to generate the
`argocd-redis` secret. Without it the secret must be created manually.

The bootstrap script (`scripts/bootstrap-argocd.sh`) handles this automatically.
If you hit this on a manual re-run, create the secret yourself:

```bash
kubectl create secret generic argocd-redis \
  --namespace argocd \
  --from-literal=auth="$(openssl rand -hex 32)"
```

---

## AppProject AAD group wiring

The `platform-project.yaml` and `workloads-project.yaml` files contain a
placeholder `<AAD_AKS_ADMINS_GROUP_OBJECT_ID>`. Replace it with the actual
group object ID before applying:

```bash
# Get the group object ID from Terraform output
GROUP_OID=$(terraform -chdir=terraform/layer1-persistent \
  output -raw aks_admins_group_object_id)

sed -i "s|<AAD_AKS_ADMINS_GROUP_OBJECT_ID>|${GROUP_OID}|g" \
  gitops/projects/platform-project.yaml \
  gitops/projects/workloads-project.yaml

kubectl apply -f gitops/projects/
```

---

## Post-bootstrap GitOps workflow

After bootstrap, the operating model is:

1. **Add a platform component** → create `gitops/platform-apps/<name>.yaml`
2. **Add a workload** → create `gitops/workload-apps/<name>.yaml`
3. **Change a Helm value** → edit the Application manifest or the referenced values file
4. **All of the above** → commit to `main` and push; ArgoCD syncs automatically

Never run `kubectl apply` directly against workload manifests after bootstrap.
All changes must go through git.
