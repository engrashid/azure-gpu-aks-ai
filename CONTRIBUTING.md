# Contributing

Thanks for your interest in improving this project! This guide explains how to
set up your environment, validate changes locally and get a pull request merged.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- Report bugs or request features with the [issue templates](https://github.com/engrashid/azure-gpu-aks-ai/issues/new/choose).
- Ask questions and share ideas in [Discussions](https://github.com/engrashid/azure-gpu-aks-ai/discussions).
- Pick up an issue labelled [`good first issue`](https://github.com/engrashid/azure-gpu-aks-ai/labels/good%20first%20issue) or [`help wanted`](https://github.com/engrashid/azure-gpu-aks-ai/labels/help%20wanted).
- Improve documentation and runbooks.

Security issues: **do not open a public issue** — see [SECURITY.md](SECURITY.md).

## Prerequisites

You do **not** need an Azure subscription to validate changes — every CI check
runs offline. Install:

| Tool | Version used in CI | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.17.1 (`>= 1.9` required) | fmt / validate |
| [TFLint](https://github.com/terraform-linters/tflint) | v0.66.0 | Terraform linting (azurerm ruleset 0.33.0) |
| [Helm](https://helm.sh/docs/intro/install/) | v4.3.1 | chart lint / template |
| [uv](https://docs.astral.sh/uv/) or Python 3.12 | — | runs Checkov 3.4.3 and yamllint 1.38.0 |
| [Node.js](https://nodejs.org/) | LTS | runs markdownlint-cli2 0.24.0 |
| [gitleaks](https://github.com/gitleaks/gitleaks) | 8.30.1 | secret scanning |
| [pre-commit](https://pre-commit.com/) | 4.x | runs all of the above on commit |

Deploying the platform additionally requires the tools listed in
[docs/prerequisites.md](docs/prerequisites.md).

## Local validation

```bash
pre-commit install          # once per clone
make validate               # run every CI check locally
# or
pre-commit run --all-files
```

Individual targets (`make help` lists them): `fmt-check`, `tf-validate`,
`tflint`, `checkov`, `helm`, `yamllint`, `markdownlint`, `gitleaks`.

## Branches and commits

- Never commit to `main` directly; it is protected and only accepts pull requests
  with passing CI.
- Branch names: `<type>/<short-description>`, e.g. `feat/keda-http-trigger`,
  `fix/firewall-acme-rule`, `docs/cost-estimate`.
- Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

  ```text
  <type>(<optional scope>): <summary in imperative mood>
  ```

  Types: `feat`, `fix`, `docs`, `ci`, `build`, `refactor`, `test`, `chore`.
  Scopes: `layer1`, `layer2`, `gitops`, `charts`, `scripts`, `docs`, `ci`.
  Breaking changes: add `!` after the type and a `BREAKING CHANGE:` footer.
- Do not add `Co-Authored-By` trailers.

## Rules for every change

- **No real identifiers:** never commit subscription, tenant, client/app, object
  or managed-identity IDs, e-mail addresses, personal domains, IPs or secrets. Use
  placeholders (`<tenant-id>`, `00000000-0000-0000-0000-000000000000`,
  `example.com`). `terraform.tfvars` is git-ignored.
- **Pin versions:** Actions by commit SHA (tag in a comment), charts, images,
  providers and tools by exact version. No `latest`.
- **Checkov:** fix findings where possible; otherwise add a justified skip.
- **Changelog:** add an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md)
  for user-visible changes.

## Pull request process

1. Fork (external contributors) or branch (maintainers) from `main`.
2. Make focused changes; run `make validate` and `make gitleaks`.
3. Open a PR using the template; link the issue it closes (`Closes #123`).
4. All CI checks must pass. A maintainer listed in [CODEOWNERS](.github/CODEOWNERS)
   reviews the change.
5. PRs are squash-merged with a Conventional Commit title; the branch is
   deleted automatically.

Infrastructure changes that alter cost, network exposure or identity should
explain the impact in the PR description and, where possible, include a
`terraform plan` summary from your own subscription (with IDs redacted).

## License

By contributing you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
