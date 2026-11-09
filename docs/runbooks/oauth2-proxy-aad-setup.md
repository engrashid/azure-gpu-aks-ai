# Runbook: oauth2-proxy AAD Application Setup

One-time procedure to register an Azure AD application for oauth2-proxy.
After this, follow `gitops/platform-apps/oauth2-proxy-secret-README.md`
to create the Kubernetes secret.

---

## Overview

oauth2-proxy sits in front of protected services (Grafana, vLLM API).
It validates AAD OIDC tokens and passes `Authorization` and `X-Auth-Request-*`
headers to upstreams. The AAD application registration provides the client
credentials needed for the OIDC flow.

---

## Step 1 — Register the AAD Application

```bash
# Set your Azure subscription and tenant
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create the app registration
APP_NAME="oauth2-proxy-qwen-dev"
APP_ID=$(az ad app create \
  --display-name "${APP_NAME}" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)

echo "Client ID (APP_ID): ${APP_ID}"
```

---

## Step 2 — Configure Redirect URIs

oauth2-proxy needs a redirect URI for the OIDC callback. Since we use
port-forward in dev, register `http://localhost:4180/oauth2/callback` as
the redirect URI, plus any ingress hostnames used in the cluster.

```bash
az ad app update \
  --id "${APP_ID}" \
  --web-redirect-uris \
    "http://localhost:4180/oauth2/callback" \
    "https://grafana.internal.qwen-dev/oauth2/callback" \
    "https://vllm.internal.qwen-dev/oauth2/callback"
```

> Add additional redirect URIs for each protected ingress hostname before
> enabling oauth2-proxy on that ingress.

---

## Step 3 — Create a Client Secret

```bash
CLIENT_SECRET=$(az ad app credential reset \
  --id "${APP_ID}" \
  --append \
  --years 1 \
  --query password -o tsv)

echo "Client Secret: ${CLIENT_SECRET}"
```

Save the secret now — Azure does not display it again.

Recommended: store it in the cluster Key Vault:

```bash
az keyvault secret set \
  --vault-name "kv-qwen-dev-<suffix>" \
  --name "oauth2-proxy-client-secret" \
  --value "${CLIENT_SECRET}"
```

---

## Step 4 — Create a Service Principal

```bash
az ad sp create --id "${APP_ID}"
```

---

## Step 5 — Update oauth2-proxy values with Tenant ID

Edit `gitops/envs/dev/oauth2-proxy-values.yaml` and replace `<TENANT_ID>`
with the actual tenant ID:

```bash
sed -i "s|<TENANT_ID>|${TENANT_ID}|g" \
  gitops/envs/dev/oauth2-proxy-values.yaml
```

Commit and push this change. The tenant ID is not a secret.

---

## Step 6 — Create the Kubernetes secret

Follow `gitops/platform-apps/oauth2-proxy-secret-README.md`:

```bash
export AAD_APP_CLIENT_ID="${APP_ID}"
export AAD_APP_CLIENT_SECRET="${CLIENT_SECRET}"

COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)

kubectl create secret generic oauth2-proxy-creds \
  --namespace oauth2-proxy \
  --from-literal=client-id="${AAD_APP_CLIENT_ID}" \
  --from-literal=client-secret="${AAD_APP_CLIENT_SECRET}" \
  --from-literal=cookie-secret="${COOKIE_SECRET}"
```

---

## Step 7 — Verify oauth2-proxy is working

```bash
# Port-forward oauth2-proxy directly
kubectl port-forward svc/oauth2-proxy -n oauth2-proxy 4180:4180

# The /ping endpoint should return 200 without auth
curl -v http://localhost:4180/ping
# Expected: HTTP/1.1 200 OK with body "OK"

# The /oauth2/auth endpoint should redirect to AAD
curl -v http://localhost:4180/oauth2/auth
# Expected: HTTP/1.1 302 Found → Location: login.microsoftonline.com/...
```

---

## Protecting an Ingress with oauth2-proxy

Add these annotations to any Ingress that should require AAD authentication:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.oauth2-proxy.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://<YOUR_INGRESS_HOST>/oauth2/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,Authorization"
```

---

## Token expiry and secret rotation

| Item | Lifetime | Rotation procedure |
|---|---|---|
| AAD client secret | 1 year (set above) | `az ad app credential reset`, update k8s secret, rollout restart |
| Cookie secret | No expiry (random) | Rotating invalidates all active sessions — users must re-login |
| CA certificate | 10 years | `kubectl delete certificate internal-ca -n cert-manager`, ArgoCD re-creates |

---

## Required AAD permissions

The app registration needs no Microsoft Graph or API permissions for
basic OIDC authentication. `email` and `openid` scopes are requested
automatically by oauth2-proxy via the standard OIDC discovery endpoint.

If you need group-membership claims (for role-based access inside the
application), add the `GroupMember.Read.All` delegated permission and
grant admin consent:

```bash
az ad app permission add \
  --id "${APP_ID}" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions bc024368-1153-4739-b217-4326f2e966d0=Scope

az ad app permission grant \
  --id "${APP_ID}" \
  --api 00000003-0000-0000-c000-000000000000 \
  --scope GroupMember.Read.All
```

---

## Troubleshooting

### Redirect URI mismatch

**Symptom:** `AADSTS50011: The redirect URI does not match the registered URIs`

**Fix:** Add the exact URI shown in the error to the app registration:

```bash
az ad app update --id "${APP_ID}" \
  --web-redirect-uris <existing-uris...> <missing-uri>
```

### Invalid client secret

**Symptom:** oauth2-proxy logs show `invalid_client` on token exchange.

**Fix:** Check the secret expiry in AAD, rotate it, recreate the k8s secret.

```bash
az ad app credential list --id "${APP_ID}"
# Look for expired credentials
```

### Cookie decode error after rotation

**Symptom:** Users see "Internal Server Error" immediately after login.

**Cause:** Existing browser cookies were signed with the old cookie-secret.

**Fix:** Users clear browser cookies for the domain, or you can temporarily
set `cookie_name = "_oauth2_proxy_v2"` in the configFile to use a fresh
cookie name, then revert after all users have re-authenticated.
