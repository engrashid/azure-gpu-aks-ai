<!-- markdownlint-disable-file MD041 -->
## Summary

<!-- What does this PR change and why? Link the issue: "Closes #123". -->

## Type of change

- [ ] `feat` — new capability
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `ci` / `build` — pipeline, tooling or dependency change
- [ ] `refactor` / `chore`

## Impact

<!-- Delete what does not apply. -->

- Layers / components touched: <!-- layer1, layer2, gitops, charts, scripts -->
- Cost impact: <!-- none / describe new SKUs or scale changes -->
- Security / network / identity impact: <!-- none / describe -->
- `terraform plan` summary (IDs redacted): <!-- optional -->

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [ ] `make validate` (or `pre-commit run --all-files`) passes locally
- [ ] `gitleaks` is clean; no real subscription/tenant/app/identity IDs, e-mails or personal domains
- [ ] All new versions are pinned (actions by SHA, charts, images, providers, tools)
- [ ] New Checkov skips (if any) include a justification
- [ ] Docs and `CHANGELOG.md` (`Unreleased`) updated where relevant
