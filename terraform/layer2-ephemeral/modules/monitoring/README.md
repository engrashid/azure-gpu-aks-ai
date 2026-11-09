# modules/monitoring — Observability Stack

Manages the Log Analytics workspace and Azure Managed Grafana instance for
Layer 2. Both resources are ephemeral and destroyed with the rest of Layer 2.

---

## ⚠️  Critical: Log Analytics daily ingestion quota

`daily_quota_gb = 5` limits ingestion to **5 GB per UTC calendar day**.

**When the cap is reached, ALL ingestion stops until UTC midnight:**

| Impact | Detail |
|---|---|
| AKS control-plane logs | kube-apiserver, kube-audit, kube-audit-admin, cluster-autoscaler are **dropped** |
| OMS node metrics | CPU / memory / disk graphs in Grafana go blank |
| Defender alerts | May not appear or may be delayed |
| Diagnostic logs | All `azurerm_monitor_diagnostic_setting` targets stop flowing |

This cap is intentional for the `dev / experimental` cost ceiling (~$2.76/GB in
East US after the first 5 GB/month free tier). **It is not suitable for
production or any workload where uninterrupted logging is required.**

### Monitoring quota usage

```bash
az monitor log-analytics workspace show \
  --resource-group <resource_group> \
  --workspace-name law-qwen-dev \
  --query "workspaceCapping"
```

Watch for `quotaNextResetTime` — ingestion resumes at that timestamp.

### Raising or removing the cap

To raise to 10 GB/day:

```hcl
daily_quota_gb = 10
```

To remove the cap entirely (unlimited, pay-per-GB):

```hcl
daily_quota_gb = -1
```

---

## Grafana authentication

Azure Managed Grafana uses **Azure Active Directory** for user authentication.
No Grafana-native username/password exists (`api_key_enabled = false`).

The Grafana system-assigned managed identity is granted **Monitoring Reader**
on the Log Analytics workspace, enabling credential-free data source
configuration.

### Required: AAD group assignment

The `grafana_admin_group_object_id` variable must reference an AAD group
(or user object ID) that should have Grafana Admin rights. Without this
`azurerm_role_assignment`, no AAD identity can sign in to the Grafana UI —
the resource will exist but show a permission error on every login.

### Adding additional Grafana roles

Use separate `azurerm_role_assignment` resources in the root module:

```hcl
# Grafana Viewer for a read-only group
resource "azurerm_role_assignment" "grafana_viewer" {
  scope                = module.monitoring.grafana_id
  role_definition_name = "Grafana Viewer"
  principal_id         = "<AAD_GROUP_OBJECT_ID>"
  principal_type       = "Group"
}
```

Available built-in roles: `Grafana Admin`, `Grafana Editor`, `Grafana Viewer`.

---

## Connecting Grafana to Log Analytics

The Azure Monitor data source is pre-configured via the system-assigned identity
(Monitoring Reader role). In the Grafana UI:

1. Navigate to **Configuration → Data sources → Azure Monitor**
2. Authentication: **Managed Identity**
3. Default subscription: select your subscription
4. Click **Save & Test** — should show "Data source is working"

---

## Outputs consumed by other modules

| Output | Consumed by |
|---|---|
| `law_workspace_id` | `module.aks` (OMS agent, Defender, diagnostic settings) |
| `grafana_endpoint` | Root `outputs.tf` (developer bookmark) |
