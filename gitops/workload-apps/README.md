# gitops/workload-apps/

This directory is the source of truth for all AI inference workloads
managed by ArgoCD.

## How it works

`workloads-root` (an ArgoCD Application created by `bootstrap-argocd.sh`)
watches this directory and applies every `*.yaml` file it finds. Each file
should be a single ArgoCD `Application` manifest.

```
gitops/workload-apps/
├── vllm-qwen.yaml     ← one Application per workload
├── model-loader.yaml
└── ...
```

## Adding a new workload

1. Create `gitops/workload-apps/<workload-name>.yaml` with a valid
   ArgoCD `Application` manifest.
2. Set `spec.project: workloads` and a destination namespace listed in
   `gitops/projects/workloads-project.yaml` (`gpu-inference`, `mfe`,
   or `backend-apis`).
3. Commit and push to `main`. ArgoCD detects the new file within 180 s.

## GPU workloads

Any Application deploying a pod that needs a GPU must ensure the Helm
chart or manifest includes the required toleration and node selector:

```yaml
tolerations:
  - key: "nvidia.com/gpu"
    operator: Equal
    value: present
    effect: NoSchedule
nodeSelector:
  gpu-type: nvidia-t4
```

The vLLM ServiceAccount (`vllm-sa` in `gpu-inference`) already exists
with its workload-identity annotation. Reference it with:

```yaml
serviceAccountName: vllm-sa
```

## Conventions

| Field | Convention |
|---|---|
| `metadata.name` | Kebab-case workload name, e.g. `vllm-qwen` |
| `spec.project` | `workloads` |
| `spec.source.targetRevision` | `main` |
| `spec.syncPolicy.automated` | `prune: true`, `selfHeal: true` |

## Labels

All Applications in this directory should carry:

```yaml
labels:
  managed-by: argocd
  app.kubernetes.io/part-of: workloads
```
