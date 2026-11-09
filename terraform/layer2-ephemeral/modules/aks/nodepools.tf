# =============================================================================
# User and GPU Node Pools
#
# Both pools land in the same aks-subnet as the system pool.
# ignore_changes on node_count prevents Terraform from fighting the cluster
# autoscaler; ignore_changes on orchestrator_version avoids spurious diffs
# after AKS automatically upgrades node images.
# =============================================================================

# ── User node pool ─────────────────────────────────────────────────────────────
# General-purpose workloads (ArgoCD, ingress, supporting services).
# Standard_D2s_v3 (2 vCPUs) keeps within dev subscription vCPU quota.
# min_count=1 to stay within quota; raise to 2 after quota increase.

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  # checkov:skip=CKV_AZURE_226:D2s_v3 cache disk (43 GiB) cannot fit 128 GiB ephemeral OS disk
  name                   = "user"
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.main.id
  vm_size                = "Standard_D2s_v3"
  mode                   = "User"
  os_disk_size_gb        = 128
  os_sku                 = var.os_sku_default
  zones                  = ["1", "2"]
  max_pods               = 100
  node_public_ip_enabled = false
  vnet_subnet_id         = var.aks_subnet_id

  auto_scaling_enabled = true
  min_count            = 1
  max_count            = 3

  node_labels = {
    "role"     = "user"
    "workload" = "apps"
  }

  upgrade_settings {
    max_surge = "1"
  }

  lifecycle {
    ignore_changes = [
      node_count,
      orchestrator_version,
    ]
  }
}

# ── GPU node pool ──────────────────────────────────────────────────────────────
# Standard_NC4as_T4_v3: 4 vCPUs, 28 GiB RAM, 1× NVIDIA T4 (16 GiB VRAM).
# min_count=0 allows the pool to scale to zero when no inference jobs run,
# eliminating GPU cost when idle.
#
# AKS installs the NVIDIA device plugin DaemonSet and drivers automatically
# when a GPU VM SKU is detected — no manual driver management needed.
# Do NOT add gpu_instance — T4 does not support MIG partitioning.
#
# Node taint "nvidia.com/gpu=present:NoSchedule" ensures only GPU-aware
# workloads (with the matching toleration) are scheduled here.
#
# "accelerator" is a reserved AKS label key — use "gpu-type" instead.
# Update nodeSelector in pod specs to match: gpu-type: nvidia-t4

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  # checkov:skip=CKV_AZURE_226:NC4as_T4_v3 temp disk (88 GiB) cannot fit 128 GiB ephemeral OS disk
  name                   = "gpu"
  kubernetes_cluster_id  = azurerm_kubernetes_cluster.main.id
  vm_size                = "Standard_NC4as_T4_v3"
  mode                   = "User"
  os_disk_size_gb        = 128
  os_sku                 = var.os_sku_default
  zones                  = [var.gpu_zone]
  max_pods               = 50
  node_public_ip_enabled = false
  vnet_subnet_id         = var.aks_subnet_id

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 2

  gpu_driver = "Install"

  node_labels = {
    "gpu-type" = "nvidia-t4"
    "workload" = "llm"
    "role"     = "gpu"
  }

  node_taints = ["nvidia.com/gpu=present:NoSchedule"]

  upgrade_settings {
    max_surge = "1"
  }

  lifecycle {
    ignore_changes = [
      node_count,
      orchestrator_version,
    ]
  }
}
