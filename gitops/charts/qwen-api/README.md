# qwen-api Helm chart

Deploys Qwen2.5-7B-Instruct-AWQ via vLLM on AKS GPU nodes (NC4as_T4_v3).

| Component | Detail |
|---|---|
| Image | `vllm/vllm-openai:v0.6.4` |
| Model | Qwen/Qwen2.5-7B-Instruct-AWQ (AWQ 4-bit, ~5 GiB) |
| GPU | 1× NVIDIA T4 (16 GiB VRAM) |
| API | OpenAI-compatible on port 8000 |
| Auth | oauth2-proxy AAD OIDC via nginx auth_request |
| Scaling | KEDA scale-to-zero (CPU trigger, configurable) |
| Storage | Azure Blob CSI FUSE2 (workload identity auth) |

## Quick render

```bash
helm template qwen-api gitops/charts/qwen-api \
  -f gitops/envs/dev/qwen-values.yaml \
  --set storage.csi.clientID=<uuid>
```

## Required values

| Key | How to get |
|---|---|
| `storage.csi.clientID` | `terraform -chdir=terraform/layer1-persistent output -raw vllm_identity_client_id` |

## Startup probe budget

The startup probe allows 660 s (10 min) before failing the pod.
See `values.yaml` for the detailed breakdown of what fills that window.
