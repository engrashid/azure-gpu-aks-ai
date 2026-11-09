# Prerequisites

What you need to **deploy** the platform. To only **validate** changes (the CI
checks), no Azure account is required — run `make validate` (see the
[Makefile](../Makefile)).

## Azure

- An Azure subscription where you can create resource groups and role
  assignments (**Owner**, or **Contributor** + **Role Based Access Control
  Administrator / User Access Administrator**). Layer 1 assigns roles to the
  managed identity and Layer 2 grants the AKS identities network and ACR roles.
- Entra ID permissions to **create security groups** (Layer 1 `modules/groups`)
  and **app registrations / client secrets** for oauth2-proxy — e.g. the
  *Groups Administrator* and *Application Developer* roles, or tenant defaults
  that allow users to create them.
- **GPU quota** for the `Standard NCASv3_T4 Family vCPUs` in your region:
  4 vCPUs per GPU node, so **8 vCPUs** for the default maximum of 2 nodes.
  Request it under *Subscriptions → Usage + quotas* before applying Layer 2;
  T4 capacity is not available in every region or zone (`gpu_zone`, default `1`).
- Regular vCPU quota for `Standard DSv3 Family` (system 2 + user up to 3
  nodes × 2 vCPUs = 10 vCPUs).
- Resource providers registered on the subscription:

  ```bash
  for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault \
            Microsoft.Storage Microsoft.Network Microsoft.ManagedIdentity \
            Microsoft.OperationalInsights Microsoft.Insights Microsoft.Dashboard; do
    az provider register --namespace "$ns"
  done
  ```

## DNS

- A domain you control (`public_domain`, e.g. `example.com`) where you can
  create A records for `chat.<domain>` and `argocd.<domain>` pointing at the
  Application Gateway public IP. cert-manager issues Let's Encrypt certificates
  via HTTP-01.

## Local tools

| Tool | Minimum version | Used by |
|---|---|---|
| Azure CLI (`az`) | 2.60 | Terraform auth, scripts |
| Terraform | 1.9 (CI uses 1.17.1) | both layers |
| kubelogin | current | Entra ID auth for kubectl/helm/Terraform providers (`local_account_disabled = true`) |
| kubectl | 1.29 | cluster operations |
| Helm | 3.14 (CI uses 4.3.1) | ArgoCD install, chart checks |
| jq, curl | jq 1.6 | scripts |
| Python 3 + pip | 3.9+ | `scripts/upload-model.sh` (huggingface_hub) |
| bash | 4.0 | `scripts/validate-and-test.sh` (macOS: `brew install bash`) |
| azcopy | optional | faster model upload |

## Accounts and access

- Your public IP address(es) for `api_server_authorized_ip_ranges`.
- A Git URL ArgoCD can read (your fork of this repository). Update the
  `repoURL` fields under `gitops/` and `gitops_repo_url` in `terraform.tfvars`.
- Optional: a Hugging Face token (`HF_TOKEN`) — not required for the public
  Qwen AWQ weights.

## Next steps

Follow [GPU stack bootstrap](runbooks/gpu-stack-bootstrap.md) and
[Qwen deployment](runbooks/qwen-deployment.md).
