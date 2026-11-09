# oauth2-proxy Credentials — Manual One-Time Setup

oauth2-proxy requires three credentials that **must never be committed to git**:
- Azure AD Application client ID
- Azure AD Application client secret
- A random cookie-signing secret

These are loaded from a Kubernetes Secret (`oauth2-proxy-creds`) that you
create once manually. ArgoCD does not manage this secret — it will never
prune or overwrite it.

## Prerequisites

Complete `docs/runbooks/oauth2-proxy-aad-setup.md` first to obtain the
AAD Application client ID and client secret.

## Create the namespace (if not already present)

```bash
kubectl create namespace oauth2-proxy --dry-run=client -o yaml | kubectl apply -f -
```

## Create the secret

```bash
export AAD_APP_CLIENT_ID=<paste-client-id-from-aad-app-registration>
export AAD_APP_CLIENT_SECRET=<paste-client-secret-from-aad-app-registration>

# Generate a cryptographically random 32-byte cookie secret
COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)

kubectl create secret generic oauth2-proxy-creds \
  --namespace oauth2-proxy \
  --from-literal=client-id="${AAD_APP_CLIENT_ID}" \
  --from-literal=client-secret="${AAD_APP_CLIENT_SECRET}" \
  --from-literal=cookie-secret="${COOKIE_SECRET}"
```

Verify:
```bash
kubectl get secret oauth2-proxy-creds -n oauth2-proxy
# Expected: Opaque secret with 3 keys
```

## Rotating credentials

If the AAD client secret expires or the cookie secret must be rotated:

```bash
kubectl delete secret oauth2-proxy-creds -n oauth2-proxy

# Re-create with updated values (same command as above).
# oauth2-proxy pods will restart automatically once the new secret is mounted.
kubectl rollout restart deployment/oauth2-proxy -n oauth2-proxy
```

## Values file reference

`gitops/envs/dev/oauth2-proxy-values.yaml` references this secret via:

```yaml
config:
  existingSecret: oauth2-proxy-creds
```

The chart mounts `client-id`, `client-secret`, and `cookie-secret` keys
from this secret into the oauth2-proxy container at startup.
