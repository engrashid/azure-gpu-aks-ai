# layer1-persistent — Persistent Infrastructure

Layer 1 owns every Azure resource that **must survive** destroy/recreate cycles
of the ephemeral Layer 2 (AKS cluster, node pools, networking, private
endpoints).  Layer 2 reads all shared identifiers via `terraform_remote_state`
pointing at `tfstate-layer2` in the same storage account.

```
layer1-persistent/
├── backend.tf          azurerm remote backend (tfstate-layer1 container)
├── providers.tf        azurerm ~> 4.0 + random ~> 3.6
├── variables.tf
├── locals.tf           shared tag map
├── main.tf             root resources + module calls
├── outputs.tf          all values consumed by Layer 2
├── bootstrap/          one-shot bootstrapper — see bootstrap/README.md
└── modules/
    ├── acr/            Azure Container Registry
    ├── keyvault/       Key Vault (random suffix against soft-delete clashes)
    ├── storage/        Generic storage account + containers
    └── identity/       User-assigned managed identity + role assignments
```

---

## Resources managed

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-qwen-persistent-dev` | |
| State storage account | `stqwentfstatedev` | Adopted from bootstrap |
| State containers | `tfstate-layer1`, `tfstate-layer2` | |
| Container Registry | `acrqwendev` | Public access disabled; Layer 2 adds PE |
| Key Vault | `kv-qwen-dev-<suffix>` | RBAC; public now; Layer 2 adds PE |
| Model storage | `stqwenmodelsdev` | Container `model-weights` |
| Managed Identity | `mi-qwen-vllm-dev` | Layer 2 adds workload-identity federation |
| Role: Blob Reader | — | Identity → model storage |
| Role: KV Secrets User | — | Identity → Key Vault |

---

## First-time apply (after bootstrap)

> **Complete the bootstrap steps first.**  
> See [`bootstrap/README.md`](./bootstrap/README.md) for the full two-step
> sequence including `terraform import` commands and state migration.

Once migration is complete:

```bash
cd terraform/layer1-persistent
terraform plan  -var-file="terraform.tfvars"
# Expected: No changes. Your infrastructure matches the configuration.
```

---

## Day-2 workflow

```bash
terraform plan  -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

---

## terraform.tfvars (never commit this file)

```hcl
subscription_id = "<YOUR_SUBSCRIPTION_ID>"
tenant_id       = "<YOUR_TENANT_ID>"
```

All other variables have production-safe defaults.

---

## Outputs consumed by Layer 2

Configure Layer 2's `terraform_remote_state` data source:

```hcl
data "terraform_remote_state" "layer1" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-qwen-persistent-dev"
    storage_account_name = "stqwentfstatedev"
    container_name       = "tfstate-layer1"
    key                  = "layer1.tfstate"
    use_azuread_auth     = true
  }
}
```

Key outputs available:

| Output | Typical Layer 2 usage |
|---|---|
| `acr_login_server` | `imagePullSecrets`, Helm values |
| `acr_id` | AcrPull role assignment for the AKS kubelet identity |
| `keyvault_id` / `keyvault_uri` | SecretProviderClass, CSI driver |
| `model_storage_account_name` | Blob CSI PersistentVolume |
| `model_storage_primary_blob_endpoint` | Blob CSI PersistentVolume |
| `model_container_name` | Blob CSI PersistentVolume |
| `vllm_identity_client_id` | `azure.workload.identity/client-id` annotation |
| `vllm_identity_id` | AKS pod identity assignment |
| `vllm_identity_principal_id` | Additional role assignments in Layer 2 |

---

## Required Azure RBAC for the operator

The developer's account (or service principal) running Terraform needs:

- **Contributor** on `rg-qwen-persistent-dev` (or subscription)
- **Storage Blob Data Contributor** on `stqwentfstatedev` (remote state)
- **Key Vault Administrator** or appropriate role for KV RBAC management
- **User Access Administrator** (to create role assignments for the managed identity)
