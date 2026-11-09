# Cost

This project deliberately does **not** publish dollar figures: Azure prices vary
by region, currency, agreement (PAYG, EA, MCA, CSP), reservations, savings plans
and change over time. Instead this page lists every billable SKU the Terraform
creates and a repeatable method to estimate your own cost.

> Always confirm with the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
> and the per-service pricing pages linked below, for **your** region and agreement.

## Billable resources

### Layer 1 – persistent (runs 24/7)

| Resource | SKU / setting in code | Billing unit | Pricing page |
|---|---|---|---|
| Container Registry | Basic | per registry per day + storage | [ACR pricing](https://azure.microsoft.com/pricing/details/container-registry/) |
| Key Vault | standard | per 10k operations | [Key Vault pricing](https://azure.microsoft.com/pricing/details/key-vault/) |
| Storage – Terraform state | StorageV2, Standard LRS, Hot | GB-month + transactions | [Blob Storage pricing](https://azure.microsoft.com/pricing/details/storage/blobs/) |
| Storage – model weights | StorageV2, Standard LRS, Hot (~5 GiB AWQ weights) | GB-month + transactions | [Blob Storage pricing](https://azure.microsoft.com/pricing/details/storage/blobs/) |
| Managed identity, Entra groups | — | no charge | — |

### Layer 2 – ephemeral (only while deployed)

| Resource | SKU / setting in code | Billing unit | Pricing page |
|---|---|---|---|
| AKS control plane | `sku_tier = "Standard"` | per cluster-hour | [AKS pricing](https://azure.microsoft.com/pricing/details/kubernetes-service/) |
| System node pool | 2 × Standard_D2s_v3, 128 GB managed OS disk | per VM-hour + disk | [Linux VM pricing](https://azure.microsoft.com/pricing/details/virtual-machines/linux/) |
| User node pool | 1–3 × Standard_D2s_v3, 128 GB OS disk | per VM-hour + disk | [Linux VM pricing](https://azure.microsoft.com/pricing/details/virtual-machines/linux/) |
| GPU node pool | 0–2 × Standard_NC4as_T4_v3, 128 GB OS disk | per VM-hour + disk | [Linux VM pricing](https://azure.microsoft.com/pricing/details/virtual-machines/linux/) |
| Azure Firewall | Basic (`AZFW_VNet`) + 2 Standard public IPs | deployment-hour + GB processed | [Azure Firewall pricing](https://azure.microsoft.com/pricing/details/azure-firewall/) |
| Application Gateway | Standard_v2, fixed capacity 1 + Standard public IP | gateway-hour + capacity-unit-hour | [App Gateway pricing](https://azure.microsoft.com/pricing/details/application-gateway/) |
| Public IP addresses | Standard, static | per IP-hour | [Public IP pricing](https://azure.microsoft.com/pricing/details/ip-addresses/) |
| Private endpoints | Key Vault, model storage | per endpoint-hour + GB | [Private Link pricing](https://azure.microsoft.com/pricing/details/private-link/) |
| Private DNS zones | one per private endpoint type | per zone-month + queries | [Azure DNS pricing](https://azure.microsoft.com/pricing/details/dns/) |
| VNet peering | hub ↔ spoke | per GB transferred | [Virtual Network pricing](https://azure.microsoft.com/pricing/details/virtual-network/) |
| Log Analytics | PerGB2018, 30-day retention, 5 GB/day cap | per GB ingested | [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/) |
| Managed Grafana | Standard | per instance-hour + active user | [Managed Grafana pricing](https://azure.microsoft.com/pricing/details/managed-grafana/) |
| Azure Bastion | Standard (`bastion_enabled = false` by default) | per hour when enabled | [Bastion pricing](https://azure.microsoft.com/pricing/details/azure-bastion/) |
| Egress bandwidth | Internet data transfer out | per GB | [Bandwidth pricing](https://azure.microsoft.com/pricing/details/bandwidth/) |

## Estimation method

1. Pick your region (default `eastus`) and currency in the Pricing Calculator.
2. Add each Layer 1 row once at 730 hours/month — this is your **floor** cost
   that persists even when the cluster is destroyed.
3. Decide on a usage profile for Layer 2, e.g. *H* hours per month that the
   stack is deployed and *G* GPU node-hours of actual inference.
4. Add the always-on Layer 2 items (AKS control plane, system and minimum user
   nodes, Firewall, App Gateway, public IPs, private endpoints, Grafana) at *H*
   hours.
5. Add GPU VMs at *G* node-hours. The pool can scale to 0 nodes, but the dev
   values (`gitops/envs/dev/qwen-values.yaml`) set KEDA `minReplicaCount: 1`, so
   one vLLM pod — and therefore one GPU node — runs while Layer 2 exists unless
   you scale it down (see the roadmap item on HTTP-based scale-to-zero).
6. Add Log Analytics ingestion (capped at 5 GB/day) and egress.
7. Check for discounts: reservations or savings plans for always-on VMs, Dev/Test
   pricing, and **spot** GPU capacity (not configured in this repo).

### Worksheet

Fill this in from the calculator; keep it out of Git if it contains negotiated
prices.

| Item | Quantity | Hours / units per month | Unit price (your region) | Monthly |
|---|---|---|---|---|
| Layer 1 (sum) | 1 | 730 h | | |
| AKS control plane (Standard) | 1 | *H* | | |
| Standard_D2s_v3 (system + user min) | 3 | *H* | | |
| Standard_NC4as_T4_v3 | — | *G* node-hours | | |
| Azure Firewall Basic | 1 | *H* + GB processed | | |
| Application Gateway Standard_v2 | 1 | *H* + capacity units | | |
| Managed Grafana Standard | 1 | *H* | | |
| Log Analytics | — | GB ingested | | |
| Other (IPs, PEs, DNS, disks, egress) | — | — | | |
| **Total** | | | | |

## Cost levers

- `terraform destroy` Layer 2 when not in use — the single biggest saving.
  Layer 1 keeps models, images, secrets and identities.
- Scale the vLLM deployment to 0 replicas outside working hours so the GPU pool
  drops to 0 nodes.
- Keep `daily_quota_gb` on Log Analytics; raise it only when needed.
- Azure Firewall and Application Gateway are fixed hourly costs while Layer 2
  exists — they dominate when the GPU pool is idle.
