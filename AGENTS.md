# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository. Keep it
short, factual and in sync with CI. [`CLAUDE.md`](CLAUDE.md) points here.

## Project in one paragraph

A private LLM inference platform on Azure Kubernetes Service: **vLLM** serving
**Qwen2.5-7B-Instruct (AWQ)** on an NVIDIA **T4** GPU node pool (autoscaling
0–2), scaled with **KEDA**, delivered by **ArgoCD** (app-of-apps), protected by
**Entra ID** via **oauth2-proxy**, using **Workload Identity** for pod → Azure
access, with all egress forced through **Azure Firewall**. Infrastructure is
**two-layer Terraform** (persistent / ephemeral) and policy-scanned with
**Checkov**.

## Layout

| Path | What lives there |
|---|---|
| `terraform/layer1-persistent/` | Long-lived resources: remote state, ACR, Key Vault, model storage, managed identity, Entra groups. `bootstrap/` creates the state backend with local state. |
| `terraform/layer2-ephemeral/` | Destroyable resources: hub-spoke network, Azure Firewall, App Gateway, AKS + GPU pool, monitoring, ArgoCD, workload secrets. Reads layer 1 via `terraform_remote_state`. |
| `gitops/bootstrap/` | ArgoCD install values and the root app-of-apps (read by layer 2 via `file()`). |
| `gitops/projects/` | ArgoCD AppProjects (`platform`, `workloads`). |
| `gitops/platform-apps/` | cert-manager, ingress-nginx, KEDA, oauth2-proxy, NVIDIA device plugin. |
| `gitops/workload-apps/` | ArgoCD Applications for `qwen-api` and `open-webui`. |
| `gitops/charts/` | In-repo Helm charts `qwen-api` and `open-webui`. |
| `gitops/envs/dev/` | Per-environment Helm values. |
| `scripts/` | Model upload, ArgoCD bootstrap/import, end-to-end validation. |
| `docs/` | Architecture, cost, prerequisites and operational runbooks. |
| `.github/` | CI workflow, Dependabot, issue/PR templates, CODEOWNERS. |

## Validation commands

Run before every push; CI (`.github/workflows/ci.yml`) runs the same checks.

```bash
make validate            # everything below
make fmt-check           # terraform fmt -check -recursive
make tf-validate         # init -backend=false + validate for each root module
make tflint              # tflint --recursive with .tflint.hcl (azurerm ruleset)
make checkov             # checkov -d terraform --config-file .checkov.yaml
make helm                # helm lint + template for both charts (defaults and dev values)
make yamllint            # yamllint --strict (Helm templates excluded)
make markdownlint        # markdownlint-cli2
make gitleaks            # gitleaks over the full git history
pre-commit run --all-files
```

Notes:

- Layer 2 reads `gitops/` files via `${path.root}/../../gitops/...`, so it
  must be validated from a full checkout of this repository layout.
- `terraform init -backend=false` never touches Azure; no credentials are needed
  for validation.
- Provider versions are locked in `.terraform.lock.hcl` (committed, multi-platform).
  After changing a provider constraint run
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64`.

## Rules (non-negotiable)

1. **Never push to `main`.** Work on a feature branch and open a pull request.
   Merge only after all CI checks are green.
2. **No real identifiers or personal data.** Never commit Azure subscription,
   tenant, app (client), object or managed-identity IDs, personal e-mail
   addresses or personal domains. Use placeholders such as `<tenant-id>`,
   `<subscription-id>`, `00000000-0000-0000-0000-000000000000` and
   `example.com`. `terraform.tfvars` is git-ignored — keep it that way.
3. **Run gitleaks before every push** (`make gitleaks` or the pre-commit hook).
4. **Pin every version.** GitHub Actions by full commit SHA with the tag in a
   comment; CLI tools, Helm charts (`targetRevision`) and container images by
   exact version. Never use `latest`, `HEAD` or floating tags.
5. **Conventional Commits** for commit messages and PR titles
   (`feat:`, `fix:`, `docs:`, `ci:`, `build:`, `chore:`, `refactor:`).
6. **No `Co-Authored-By` trailers** in commits.
7. **Checkov skips must be justified.** Add them to `.checkov.yaml` or as an
   inline `# checkov:skip=CKV_...:reason` comment — never without a reason.
8. **Keep CI least-privilege.** Workflows default to `permissions: contents: read`;
   grant more per job only when required.

## Conventions

- Terraform: `terraform fmt` style, one module per concern, every module has a
  `versions.tf` with `required_version` and `required_providers`.
- Naming: `<type>-<prefix>-<purpose>-<environment>` (e.g. `rg-qwen-ephemeral-dev`).
- Helm: chart changes bump `version` in `Chart.yaml`; image tags live in
  `values.yaml` and are overridden per environment in `gitops/envs/<env>/`.
- Docs: update `CHANGELOG.md` (Keep a Changelog, `Unreleased` section) for
  user-visible changes; keep relative links valid (CI checks them offline).
