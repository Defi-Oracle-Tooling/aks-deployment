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

# Network-specific infrastructure requirements
network_requirements = {
    "mainnet": {
        "min_node_count": 4,
        "vm_size": "Standard_D8s_v3",
        "availability_zones": ["1", "2", "3"],
        "auto_scaling": true,
        "node_labels": {
            "environment": "production",
            "network": "mainnet"
        }
    },
    "testnet": {
        "min_node_count": 2,
        "vm_size": "Standard_D4s_v3",
        "availability_zones": ["1", "2"],
        "auto_scaling": true,
        "node_labels": {
            "environment": "staging",
            "network": "testnet"
        }
    },
    "devnet": {
        "min_node_count": 1,
        "vm_size": "Standard_D2s_v3",
        "availability_zones": ["1"],
        "auto_scaling": false,
        "node_labels": {
            "environment": "development",
            "network": "devnet"
        }
    }
}

# Validate AKS cluster configuration
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type
    req := network_requirements[network_type]

    to_number(resource.values.default_node_pool[0].node_count) < req.min_node_count
    msg := sprintf("Node count must be at least %v for %v", [req.min_node_count, network_type])
}

deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type
    req := network_requirements[network_type]

    resource.values.default_node_pool[0].vm_size != req.vm_size
    msg := sprintf("VM size must be %v for %v", [req.vm_size, network_type])
}

# Validate availability zones
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type
    req := network_requirements[network_type]

    zones := resource.values.default_node_pool[0].availability_zones
    required_zones := req.availability_zones
    missing_zones := required_zones - zones

    count(missing_zones) > 0
    msg := sprintf("Missing required availability zones %v for %v", [missing_zones, network_type])
}

# Validate auto-scaling configuration
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type
    req := network_requirements[network_type]

    req.auto_scaling == true
    not resource.values.default_node_pool[0].enable_auto_scaling
    msg := sprintf("Auto-scaling must be enabled for %v", [network_type])
}

# Validate node labels
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type
    req := network_requirements[network_type]

    labels := resource.values.default_node_pool[0].node_labels
    required_labels := req.node_labels
    missing_labels := {k | required_labels[k]; not labels[k]}

    count(missing_labels) > 0
    msg := sprintf("Missing required node labels %v for %v", [missing_labels, network_type])
}

# Network-specific security requirements
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type

    network_type == "mainnet"
    not resource.values.role_based_access_control_enabled
    msg := "RBAC must be enabled for mainnet clusters"
}

deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type

    network_type == "mainnet"
    not resource.values.azure_active_directory_integration
    msg := "Azure AD integration must be enabled for mainnet clusters"
}

# Validate monitoring configuration
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type

    network_type == "mainnet"
    not resource.values.addon_profile[0].oms_agent[0].enabled
    msg := "OMS agent must be enabled for mainnet clusters"
}

# Validate network policy configuration
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := resource.values.tags.network_type

    network_type == "mainnet"
    not resource.values.network_profile[0].network_policy == "azure"
    msg := "Azure network policy must be enabled for mainnet clusters"
}

# Network-specific validations for AKS clusters
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "mainnet"
    not resource.values.sku_tier == "Paid"

    msg := "Mainnet AKS clusters must use paid SKU tier for SLA guarantees"
}

deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "mainnet"
    not resource.values.network_profile[0].network_plugin == "azure"

    msg := "Mainnet AKS clusters must use Azure CNI networking"
}

# Network-specific node pool validations
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster_node_pool"
    resource.values.network_type == "mainnet"
    not resource.values.vm_size matches "Standard_D[0-9]+s_v4"

    msg := "Mainnet node pools must use v4 series compute-optimized VMs"
}

# Network-specific availability requirements
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "mainnet"
    not resource.values.availability_zones

    msg := "Mainnet AKS clusters must be deployed across availability zones"
}

# Testnet specific rules - less strict
warn[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "testnet"
    not resource.values.availability_zones

    msg := "Warning: Consider using availability zones for testnet clusters"
}

# Network-specific backup requirements
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "mainnet"
    not resource.values.maintenance_window

    msg := "Mainnet clusters must have maintenance windows defined"
}

# Resource tagging requirements
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    not resource.values.tags.network_type

    msg := sprintf("Resource %v must be tagged with network_type", [resource.address])
}

# Network-specific monitoring requirements
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    resource.values.network_type == "mainnet"
    not resource.values.monitor_metrics

    msg := "Mainnet clusters must have Azure Monitor metrics enabled"
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