# bootstrap — Layer 1 Bootstrap

This sub-directory uses **local state** to create the resource group and the
Terraform state storage account that both Layer 1 and Layer 2 will use.
It must be applied exactly once per environment, before the main
`layer1-persistent` configuration is initialised with its remote backend.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.9 |
| AzureRM provider | ~> 4.0 (downloaded automatically) |
| Azure CLI | any recent; used for authentication |

Log in and set the correct subscription:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

Grant yourself **Storage Blob Data Contributor** and
**Storage Account Contributor** on the subscription (or resource group) so
Terraform can manage the state container.

---

## Step 1 — Apply bootstrap (local state)

```bash
cd terraform/layer1-persistent/bootstrap

# Create a tfvars file (never commit it)
cat > terraform.tfvars <<'EOF'
subscription_id = "<subscription-id>"
EOF

terraform init
terraform plan  -var-file="terraform.tfvars" -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Record the outputs — you will need them in Step 2:

```
resource_group_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev"
resource_group_name = "rg-qwen-persistent-dev"
state_storage_account_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev"
state_storage_account_name = "stqwentfstatedev"
tfstate_layer1_container_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev/blobServices/default/containers/tfstate-layer1"
tfstate_layer2_container_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwentfstatedev/blobServices/default/containers/tfstate-layer2"
```

---

## Step 2 — Import bootstrap resources into layer1-persistent

The main `layer1-persistent` configuration manages **all** persistent
resources, including the state storage account created here.  
Import the bootstrap-created resources so layer1 can adopt them without
recreating them.

> **Why the `mv` below?**  
> `terraform import` does not accept `-backend=false` — that flag is only
> valid for `terraform init`.  If `backend.tf` is present when you run
> `terraform import`, Terraform reads the azurerm backend block, finds it
> uninitialised (the storage account was just created), and exits with
> *"please run terraform init"*.  Temporarily moving `backend.tf` aside
> forces Terraform to use a plain local backend for the import + apply
> phase; Step 4 restores it and migrates the state.

```bash
cd ../   # now in terraform/layer1-persistent/

# Create layer1 tfvars (never commit it)
cat > terraform.tfvars <<'EOF'
subscription_id = "<subscription-id>"
tenant_id       = "<tenant-id>"
EOF

SUB="<subscription-id>"
RG="rg-qwen-persistent-dev"
SA="stqwentfstatedev"

# Temporarily move backend.tf aside so Terraform uses local state.
# Restored in Step 4 before state migration.
mv backend.tf backend.tf.disabled

# Init with local state (downloads providers)
terraform init

# Import resource group
terraform import \
  -var-file="terraform.tfvars" \
  azurerm_resource_group.persistent \
  "/subscriptions/${SUB}/resourceGroups/${RG}"

# Import state storage account
terraform import \
  -var-file="terraform.tfvars" \
  azurerm_storage_account.tfstate \
  "/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${SA}"

# Import state containers
terraform import \
  -var-file="terraform.tfvars" \
  azurerm_storage_container.tfstate_layer1 \
  "/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${SA}/blobServices/default/containers/tfstate-layer1"

terraform import \
  -var-file="terraform.tfvars" \
  azurerm_storage_container.tfstate_layer2 \
  "/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${SA}/blobServices/default/containers/tfstate-layer2"
```

---

## Step 3 — Apply the remaining layer1 resources (local state)

```bash
terraform plan  -var-file="terraform.tfvars" -out=layer1.tfplan
terraform apply layer1.tfplan
```

The plan should show **no changes** for the four imported resources and will
create ACR, Key Vault, model storage, and the managed identity.

Example outputs after apply:

```text
acr_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.ContainerRegistry/registries/acrqwendev"
acr_login_server = "acrqwendev.azurecr.io"
acr_name = "acrqwendev"
keyvault_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.KeyVault/vaults/kv-qwen-dev-xxxx"
keyvault_name = "kv-qwen-dev-xxxx"
keyvault_uri = "https://kv-qwen-dev-xxxx.vault.azure.net/"
location = "eastus"
model_container_name = "model-weights"
model_storage_account_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.Storage/storageAccounts/stqwenmodelsdev"
model_storage_account_name = "stqwenmodelsdev"
model_storage_primary_blob_endpoint = "https://stqwenmodelsdev.blob.core.windows.net/"
resource_group_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev"
resource_group_name = "rg-qwen-persistent-dev"
state_storage_account_name = "stqwentfstatedev"
vllm_identity_client_id = "<vllm-identity-client-id>"
vllm_identity_id = "/subscriptions/<subscription-id>/resourceGroups/rg-qwen-persistent-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mi-qwen-vllm-dev"
vllm_identity_principal_id = "<vllm-identity-principal-id>"
vllm_identity_tenant_id = "<tenant-id>"
```

---

## Step 4 — Migrate local state to the remote Azure backend

```bash
# Restore the remote backend configuration (moved aside in Step 2)
mv backend.tf.disabled backend.tf
```

Assign yourself **Storage Blob Data Contributor** on `stqwentfstatedev` (or
use the connection-string fallback in the `azurerm` backend if RBAC is not yet
propagated), then:

```bash
# Re-initialise WITH the backend — Terraform detects existing local state
# and prompts to copy it to the remote container.
terraform init -migrate-state
```

Answer `yes` when prompted to migrate.

Verify the state is now remote:

```bash
terraform plan -var-file="terraform.tfvars"
# Expected: No changes. Your infrastructure matches the configuration.
```

---

## Day-2 workflow (after migration)

```bash
cd terraform/layer1-persistent
terraform init                                      # already using remote backend
terraform plan  -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

The bootstrap directory is no longer used after migration completes. Its
**local** `terraform.tfstate` file can be deleted once you have confirmed the
remote state is healthy:

```bash
rm terraform/layer1-persistent/bootstrap/terraform.tfstate
```
