# gitops/platform-apps/

This directory is the source of truth for all platform-layer applications
managed by ArgoCD.

## How it works

`platform-root` (an ArgoCD Application created by `bootstrap-argocd.sh`)
watches this directory and applies every `*.yaml` file it finds. Each file
should be a single ArgoCD `Application` manifest.

```
gitops/platform-apps/
├── ingress-nginx.yaml     ← one Application per component
├── cert-manager.yaml
├── keda.yaml
└── ...
```

## Adding a new platform component

1. Create `gitops/platform-apps/<component-name>.yaml` with a valid
   ArgoCD `Application` manifest.
2. Set `spec.project: platform` and a destination namespace that is
   listed in `gitops/projects/platform-project.yaml`.
3. Commit and push to `main`. ArgoCD detects the new file within
   `timeout.reconciliation` (180 s) and begins syncing automatically.

## Conventions

| Field | Convention |
|---|---|
| `metadata.name` | Kebab-case component name, e.g. `ingress-nginx` |
| `spec.project` | `platform` |
| `spec.source.targetRevision` | `main` |
| `spec.syncPolicy.automated` | `prune: true`, `selfHeal: true` |
| `spec.syncPolicy.syncOptions` | `ServerSideApply=true`, `CreateNamespace=true` |

## Labels

All Applications in this directory should carry:

```yaml
labels:
  managed-by: argocd
  app.kubernetes.io/part-of: platform
```
