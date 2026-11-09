# =============================================================================
# AKS Cluster — PUBLIC API server (Option A)
#
# The API server is reachable from the internet but locked to
# var.api_server_authorized_ip_ranges so only listed developer IPs can
# connect. All node traffic, egress, ACR pulls, KV access, and blob reads
# remain private via the spoke VNet / Azure Firewall / Private Endpoints.
#
# Workload Identity requires both oidc_issuer_enabled AND
# workload_identity_enabled to be explicitly set. AKS 1.34+ changed the
# OIDC default so we set them unambiguously here.
# =============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  # checkov:skip=CKV_AZURE_115:Public API server is intentional — Option A design (public API + authorized IP allowlist)
  # checkov:skip=CKV_AZURE_116:Azure Policy add-on not required for dev/experimental environment
  # checkov:skip=CKV_AZURE_117:CMK disk encryption requires a Disk Encryption Set in Layer 1 — out of scope
  # checkov:skip=CKV_AZURE_172:CSI Driver not deployed yet — secrets autorotation configured in ArgoCD phase
  # checkov:skip=CKV_AZURE_226:Selected VM SKUs (D2s_v3) have insufficient cache disk (43 GiB) for 128 GiB ephemeral OS disk
  name                = "aks-${var.name_prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = "aks-${var.name_prefix}-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # ── Tier & access control ───────────────────────────────────────────────────

  sku_tier                  = "Standard"
  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ── Upgrades ────────────────────────────────────────────────────────────────
  # patch: auto-apply patch releases; minor upgrades remain manual.
  # NodeImage: keeps node OS images current without touching k8s version.

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # ── API server access (PUBLIC + IP allowlist) ───────────────────────────────

  private_cluster_enabled = false

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  # ── Cluster identity ────────────────────────────────────────────────────────

  identity {
    type = "SystemAssigned"
  }

  # ── System node pool ────────────────────────────────────────────────────────
  # only_critical_addons_enabled isolates system pods (coredns, konnectivity,
  # metrics-server) away from user workloads.

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D2s_v3"
    node_count                   = 2
    auto_scaling_enabled         = false
    os_disk_size_gb              = 128
    os_disk_type                 = "Managed"
    os_sku                       = var.os_sku_default
    zones                        = ["1", "2"]
    only_critical_addons_enabled = true
    max_pods                     = 50
    node_public_ip_enabled       = false
    vnet_subnet_id               = var.aks_subnet_id
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # ── Network profile ─────────────────────────────────────────────────────────
  # overlay mode: pod IPs are drawn from pod_cidr, not from the subnet CIDR,
  # preserving subnet address space for other resources.
  # outbound_type=userDefinedRouting: all egress goes through the Azure Firewall
  # UDR set on aks-subnet; no NAT gateway or load-balancer SNAT needed.

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting"
    pod_cidr            = "172.17.0.0/16"
  }

  # ── AAD RBAC ─────────────────────────────────────────────────────────────────
  # azure_rbac_enabled maps Azure RBAC roles (e.g. Azure Kubernetes Service
  # Cluster Admin Role) to cluster access. admin_group_object_ids grants the
  # listed AAD groups full cluster-admin rights via the built-in binding.

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
  }

  # ── Application Gateway Ingress Controller (AGIC) ────────────────────────────
  # Addon-mode AGIC: AKS manages the controller pod and its MSI.
  # gateway_id references the pre-existing App Gateway created in the networking
  # module. AGIC's MSI is granted Contributor on the AGW in rbac.tf.

  ingress_application_gateway {
    gateway_id = var.app_gateway_id
  }

  # ── Observability ────────────────────────────────────────────────────────────

  oms_agent {
    log_analytics_workspace_id      = var.law_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  microsoft_defender {
    log_analytics_workspace_id = var.law_workspace_id
  }

  # ── Cluster autoscaler profile ───────────────────────────────────────────────

  auto_scaler_profile {
    scan_interval                 = "10s"
    scale_down_unneeded           = "10m"
    scale_down_delay_after_add    = "10m"
    scale_down_delay_after_delete = "10s"
    max_graceful_termination_sec  = "600"
    empty_bulk_delete_max         = "10"
    new_pod_scale_up_delay        = "0s"
    skip_nodes_with_local_storage = false
    skip_nodes_with_system_pods   = true
    balance_similar_node_groups   = false
  }

  # ── Lifecycle ────────────────────────────────────────────────────────────────
  # kubernetes_version drifts after automatic_upgrade_channel applies a patch.
  # orchestrator_version on the node pool follows the same cadence.
  # Ignoring both prevents Terraform from reverting auto-applied upgrades.

  lifecycle {
    ignore_changes = [
      kubernetes_version,
      default_node_pool[0].orchestrator_version,
    ]
  }
}
