output "aks_admins_object_id" {
  description = "Object ID of the aks-admins group — used as admin_group_object_ids in AKS"
  value       = azuread_group.aks_admins.object_id
}

output "grafana_admins_object_id" {
  description = "Object ID of the grafana-admins group — used as grafana_admin_group_object_id"
  value       = azuread_group.grafana_admins.object_id
}

output "vllm_readers_object_id" {
  description = "Object ID of the vllm-readers group — for k8s RBAC role bindings"
  value       = azuread_group.vllm_readers.object_id
}
