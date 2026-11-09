# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| `main` | ✅ |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public issues,
discussions or pull requests.**

Use GitHub **private vulnerability reporting**:

1. Go to the [Security tab](https://github.com/engrashid/azure-gpu-aks-ai/security)
   of this repository.
2. Click **Report a vulnerability** (or open
   <https://github.com/engrashid/azure-gpu-aks-ai/security/advisories/new> directly).
3. Describe the issue, affected files/versions, reproduction steps and impact.

You can expect an acknowledgement within **7 days**. We will keep you informed
while a fix is prepared and credit you in the advisory unless you prefer
otherwise.

## Scope

In scope:

- Terraform, Helm charts, ArgoCD manifests and scripts in this repository —
  e.g. insecure defaults, overly broad RBAC or network rules, secret exposure.

Out of scope:

- Vulnerabilities in upstream projects (vLLM, Open WebUI, ArgoCD, AKS, …) —
  please report those upstream.
- Issues that require an already-compromised Azure subscription or cluster
  admin credentials.

## Hardening already in place

- Secret scanning with push protection and gitleaks in CI.
- Checkov policy scanning of all Terraform (skips documented in `.checkov.yaml`).
- No static cloud credentials in the cluster (Workload Identity), Entra ID-only
  cluster access, egress through Azure Firewall.
