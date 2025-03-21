package terraform

# AKS cluster validations
deny_aks[msg] {
    input.resource.azurerm_kubernetes_cluster
    cluster := input.resource.azurerm_kubernetes_cluster[_]
    not cluster.private_cluster_enabled
    msg = sprintf("AKS cluster %v must be private", [cluster.name])
}

deny_aks[msg] {
    input.resource.azurerm_kubernetes_cluster
    cluster := input.resource.azurerm_kubernetes_cluster[_]
    not startswith(cluster.kubernetes_version, "1.25")
    msg = sprintf("AKS cluster %v must use Kubernetes version 1.25 or higher", [cluster.name])
}

# Network security validations
deny_network[msg] {
    input.resource.azurerm_virtual_network
    vnet := input.resource.azurerm_virtual_network[_]
    not contains(vnet.address_space[0], "10.0.0.0")
    msg = sprintf("VNet %v must use approved address space", [vnet.name])
}

deny_network[msg] {
    input.resource.azurerm_subnet
    subnet := input.resource.azurerm_subnet[_]
    not subnet.service_endpoints[_] == "Microsoft.KeyVault"
    msg = sprintf("Subnet %v must have KeyVault service endpoint", [subnet.name])
}

# Storage security validations
deny_storage[msg] {
    input.resource.azurerm_storage_account
    storage := input.resource.azurerm_storage_account[_]
    not storage.enable_https_traffic_only
    msg = sprintf("Storage account %v must enforce HTTPS", [storage.name])
}

deny_storage[msg] {
    input.resource.azurerm_storage_account
    storage := input.resource.azurerm_storage_account[_]
    not storage.min_tls_version == "TLS1_2"
    msg = sprintf("Storage account %v must use TLS 1.2", [storage.name])
}

# Key Vault validations
deny_keyvault[msg] {
    input.resource.azurerm_key_vault
    keyvault := input.resource.azurerm_key_vault[_]
    not keyvault.purge_protection_enabled
    msg = sprintf("Key Vault %v must have purge protection enabled", [keyvault.name])
}

deny_keyvault[msg] {
    input.resource.azurerm_key_vault
    keyvault := input.resource.azurerm_key_vault[_]
    not keyvault.sku_name == "premium"
    msg = sprintf("Key Vault %v must use premium SKU", [keyvault.name])
}

# Resource naming convention validations
deny_naming[msg] {
    resource := input.resource[type][name]
    not startswith(name, "besu-")
    msg = sprintf("Resource %v must follow naming convention", [name])
}

# Resource group validations
deny_resource_group[msg] {
    input.resource.azurerm_resource_group
    rg := input.resource.azurerm_resource_group[_]
    not rg.location == "westeurope"
    not rg.location == "eastus"
    msg = sprintf("Resource group %v must be in approved regions", [rg.name])
}

# Monitoring validations
deny_monitoring[msg] {
    input.resource.azurerm_monitor_diagnostic_setting
    diag := input.resource.azurerm_monitor_diagnostic_setting[_]
    not diag.log[_].retention_policy.days == 30
    msg = sprintf("Diagnostic setting %v must retain logs for 30 days", [diag.name])
}

# Tag validations
required_tags = {
    "Environment",
    "ManagedBy",
    "Network",
    "CostCenter"
}

deny_tags[msg] {
    resource := input.resource[type][name]
    tags := {tag | resource.tags[tag]}
    missing := required_tags - tags
    count(missing) > 0
    msg = sprintf("Resource %v missing required tags: %v", [name, missing])
}

# Cost optimization validations
deny_cost[msg] {
    input.resource.azurerm_kubernetes_cluster
    cluster := input.resource.azurerm_kubernetes_cluster[_]
    not cluster.auto_scaler_profile
    msg = sprintf("AKS cluster %v must have autoscaling enabled", [cluster.name])
}

# Aggregate all denials
deny[msg] {
    msg := deny_aks[_]
}

deny[msg] {
    msg := deny_network[_]
}

deny[msg] {
    msg := deny_storage[_]
}

deny[msg] {
    msg := deny_keyvault[_]
}

deny[msg] {
    msg := deny_naming[_]
}

deny[msg] {
    msg := deny_resource_group[_]
}

deny[msg] {
    msg := deny_monitoring[_]
}

deny[msg] {
    msg := deny_tags[_]
}

deny[msg] {
    msg := deny_cost[_]
}