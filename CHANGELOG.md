# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Architecture diagram redrawn in draw.io with official Azure icons
  (`docs/images/architecture.drawio` + PNG), replacing the Mermaid diagram in
  the README.

## [0.1.0] - 2026-11-09

First tagged release of the public reference platform.

### Added

- Two-layer Terraform: `layer1-persistent` (state backend bootstrap, ACR, Key
  Vault, model storage, managed identity, Entra groups) and `layer2-ephemeral`
  (hub-spoke network, Azure Firewall Basic, Application Gateway Standard_v2, AKS
  with T4 GPU pool 0–2, Log Analytics, Managed Grafana, ArgoCD, workload secrets).
- ArgoCD app-of-apps with `platform` and `workloads` AppProjects; platform apps
  for cert-manager, ingress-nginx, KEDA, oauth2-proxy and the NVIDIA device plugin.
- In-repo Helm charts `qwen-api` (vLLM v0.6.4 serving Qwen2.5-7B-Instruct AWQ)
  and `open-webui`.
- Runbooks for bootstrap, Qwen deployment, oauth2-proxy/Entra ID setup and vLLM
  troubleshooting; helper scripts for model upload and ArgoCD bootstrap.
- CI pipeline: Terraform fmt/validate, TFLint, Checkov, Helm lint/template,
  yamllint, markdownlint, offline link check and gitleaks; Dependabot for GitHub
  Actions and Terraform providers; pre-commit hooks and `make validate`.
- Community health files: Apache-2.0 license, contributing guide, Code of
  Conduct, security policy, support guide, CODEOWNERS, issue and PR templates,
  `AGENTS.md`.
- Documentation: architecture, cost estimation methodology and prerequisites.

### Changed

- Provider versions are pinned with committed multi-platform `.terraform.lock.hcl`
  files for each root module.

[Unreleased]: https://github.com/engrashid/azure-gpu-aks-ai/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/engrashid/azure-gpu-aks-ai/releases/tag/v0.1.0
