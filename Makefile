# Local validation — mirrors .github/workflows/ci.yml.
# Requires: terraform, tflint, helm, uv (for yamllint/checkov), node/npx, gitleaks.
# Versions are pinned to match CI.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

TF_DIRS := terraform/layer1-persistent terraform/layer1-persistent/bootstrap terraform/layer2-ephemeral
CHARTS  := qwen-api open-webui

CHECKOV_VERSION      := 3.4.3
YAMLLINT_VERSION     := 1.38.0
MARKDOWNLINT_VERSION := 0.24.0

.PHONY: help validate fmt fmt-check tf-validate tflint checkov helm yamllint markdownlint gitleaks pre-commit

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

validate: fmt-check tf-validate tflint checkov helm yamllint markdownlint gitleaks ## Run every CI check locally

fmt: ## Format Terraform files in place
	terraform fmt -recursive terraform

fmt-check: ## terraform fmt -check
	terraform fmt -check -recursive -diff terraform

tf-validate: ## terraform init -backend=false + validate for every root module
	@for d in $(TF_DIRS); do \
	  echo "==> $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false -lockfile=readonly >/dev/null; \
	  terraform -chdir=$$d validate -no-color; \
	done

tflint: ## tflint (recursive)
	tflint --init
	tflint --recursive --config "$(CURDIR)/.tflint.hcl" --format compact

checkov: ## Checkov policy scan using .checkov.yaml
	uvx --from checkov==$(CHECKOV_VERSION) checkov -d terraform --config-file .checkov.yaml --framework terraform --compact --quiet

helm: ## helm lint + template for both charts (defaults and dev values)
	helm lint gitops/charts/qwen-api
	helm lint gitops/charts/qwen-api -f gitops/envs/dev/qwen-values.yaml
	helm template ci gitops/charts/qwen-api -f gitops/envs/dev/qwen-values.yaml >/dev/null
	helm lint gitops/charts/open-webui
	helm lint gitops/charts/open-webui -f gitops/envs/dev/open-webui-values.yaml
	helm template ci gitops/charts/open-webui -f gitops/envs/dev/open-webui-values.yaml >/dev/null

yamllint: ## yamllint (strict)
	uvx --from yamllint==$(YAMLLINT_VERSION) yamllint --strict .

markdownlint: ## markdownlint-cli2
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION)

gitleaks: ## Secret scan of the full git history
	gitleaks git --no-banner --redact .

pre-commit: ## Run all pre-commit hooks against every file
	pre-commit run --all-files
