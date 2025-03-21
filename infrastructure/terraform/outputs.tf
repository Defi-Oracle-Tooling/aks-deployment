output "cluster_ids" {
  description = "Map of region to AKS cluster IDs"
  value       = { for k, v in module.besu_network : k => v.cluster_id }
}

output "resource_groups" {
  description = "Map of region to resource group names"
  value       = { for k, v in module.besu_network : k => v.resource_group_name }
}

output "kube_config" {
  description = "Kubeconfig for each AKS cluster"
  value       = { for k, v in module.besu_network : k => v.kube_config }
  sensitive   = true
}

output "node_resource_groups" {
  description = "Resource groups containing AKS node pools"
  value       = { for k, v in module.besu_network : k => v.node_resource_group }
}

output "monitoring" {
  description = "Monitoring stack details"
  value = {
    prometheus_endpoint = module.monitoring.prometheus_endpoint
    grafana_endpoint    = module.monitoring.grafana_endpoint
    alertmanager_endpoint = module.monitoring.alertmanager_endpoint
  }
}

output "network" {
  description = "Network configuration details"
  value = {
    vnet_ids     = { for k, v in module.besu_network : k => v.vnet_id }
    subnet_ids   = { for k, v in module.besu_network : k => v.subnet_ids }
  }
}

output "aks_cluster_ids" {
  description = "Map of AKS cluster IDs by region"
  value = {
    for region, cluster in azurerm_kubernetes_cluster.besu :
    region => cluster.id
  }
}

output "aks_cluster_endpoints" {
  description = "Map of AKS cluster endpoints by region"
  value = {
    for region, cluster in azurerm_kubernetes_cluster.besu :
    region => cluster.fqdn
  }
  sensitive = true
}

output "key_vault_ids" {
  description = "Map of Key Vault IDs by region"
  value = {
    for region, kv in azurerm_key_vault.besu :
    region => kv.id
  }
}

output "vnet_ids" {
  description = "Map of VNet IDs by region"
  value = {
    for region, vnet in azurerm_virtual_network.besu :
    region => vnet.id
  }
}

output "log_analytics_workspace_ids" {
  description = "Map of Log Analytics workspace IDs by region"
  value = {
    for region, workspace in azurerm_log_analytics_workspace.besu :
    region => workspace.id
  }
}

output "aks_node_resource_groups" {
  description = "Map of AKS node resource group names by region"
  value = {
    for region, cluster in azurerm_kubernetes_cluster.besu :
    region => cluster.node_resource_group
  }
}

output "aks_kubelet_identities" {
  description = "Map of AKS kubelet managed identities by region"
  value = {
    for region, cluster in azurerm_kubernetes_cluster.besu :
    region => cluster.kubelet_identity[0].object_id
  }
  sensitive = true
}

output "subnet_ids" {
  description = "Map of AKS subnet IDs by region"
  value = {
    for region, subnet in azurerm_subnet.aks :
    region => subnet.id
  }
}

output "node_pools" {
  description = "Details of the node pools created for each region"
  value = {
    for key, pool in azurerm_kubernetes_cluster_node_pool.besu : key => {
      name      = pool.name
      vm_size   = pool.vm_size
      min_count = pool.min_count
      max_count = pool.max_count
    }
  }
}

output "monitoring_info" {
  description = "Monitoring configuration details"
  value = {
    for region, workspace in azurerm_log_analytics_workspace.besu : region => {
      workspace_id   = workspace.id
      workspace_name = workspace.name
      retention_days = workspace.retention_in_days
    }
  }
}