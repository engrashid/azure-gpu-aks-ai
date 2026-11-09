# =============================================================================
# AAD Groups
#
# Three security groups for this stack:
#
#   aks-<prefix>-admins       — kubectl cluster-admin (AKS AAD RBAC)
#   grafana-<prefix>-admins   — Grafana UI admin
#   aks-<prefix>-vllm-readers — read-only kubectl for the app/inference team
#
# The operator running Terraform is added as the initial member of all three.
# Add further members via var.additional_member_object_ids.
# The vLLM managed identity is NOT a group member — it authenticates via
# workload identity federation, not AAD group membership.
# =============================================================================

data "azuread_client_config" "current" {}

# ── Groups ─────────────────────────────────────────────────────────────────────

resource "azuread_group" "aks_admins" {
  display_name     = "aks-${var.prefix}-admins"
  mail_nickname    = "aks-${var.prefix}-admins"
  security_enabled = true
  description      = "kubectl cluster-admin access for the ${var.prefix} AKS cluster"
}

resource "azuread_group" "grafana_admins" {
  display_name     = "grafana-${var.prefix}-admins"
  mail_nickname    = "grafana-${var.prefix}-admins"
  security_enabled = true
  description      = "Grafana Admin role for the ${var.prefix} Managed Grafana instance"
}

resource "azuread_group" "vllm_readers" {
  display_name     = "aks-${var.prefix}-vllm-readers"
  mail_nickname    = "aks-${var.prefix}-vllm-readers"
  security_enabled = true
  description      = "Read-only kubectl access to the gpu-inference namespace"
}

# ── Operator membership (initial member — the identity running Terraform) ──────

resource "azuread_group_member" "operator_aks_admins" {
  group_object_id  = azuread_group.aks_admins.object_id
  member_object_id = data.azuread_client_config.current.object_id
}

resource "azuread_group_member" "operator_grafana_admins" {
  group_object_id  = azuread_group.grafana_admins.object_id
  member_object_id = data.azuread_client_config.current.object_id
}

resource "azuread_group_member" "operator_vllm_readers" {
  group_object_id  = azuread_group.vllm_readers.object_id
  member_object_id = data.azuread_client_config.current.object_id
}

# ── Additional members (optional) ─────────────────────────────────────────────

resource "azuread_group_member" "extra_aks_admins" {
  for_each = toset(var.additional_admin_member_object_ids)

  group_object_id  = azuread_group.aks_admins.object_id
  member_object_id = each.value
}

resource "azuread_group_member" "extra_grafana_admins" {
  for_each = toset(var.additional_admin_member_object_ids)

  group_object_id  = azuread_group.grafana_admins.object_id
  member_object_id = each.value
}

resource "azuread_group_member" "extra_vllm_readers" {
  for_each = toset(var.additional_reader_member_object_ids)

  group_object_id  = azuread_group.vllm_readers.object_id
  member_object_id = each.value
}
