package main

import data.kubernetes
import data.terraform

# Deny deployments that don't meet security requirements
deny[msg] {
    kubernetes.container
    not kubernetes.container.security_context.runAsNonRoot
    msg = sprintf("Container %v must run as non-root", [kubernetes.container.name])
}

# Enforce resource limits
deny[msg] {
    kubernetes.container
    not kubernetes.container.resources.limits
    msg = sprintf("Container %v must have resource limits", [kubernetes.container.name])
}

# Enforce network policies
deny[msg] {
    kubernetes.namespace.metadata.name == "besu"
    not kubernetes.networkpolicy
    msg = "Besu namespace must have network policies"
}

# Enforce Azure Key Vault integration
deny[msg] {
    kubernetes.pod
    kubernetes.pod.metadata.namespace == "besu"
    not kubernetes.pod.spec.volumes[_].azureKeyVault
    msg = "Besu pods must use Azure Key Vault for secrets"
}

# Terraform security rules
deny[msg] {
    terraform.resource.azurerm_kubernetes_cluster
    not terraform.resource.azurerm_kubernetes_cluster.network_profile.network_policy
    msg = "AKS clusters must have network policies enabled"
}

deny[msg] {
    terraform.resource.azurerm_kubernetes_cluster
    not terraform.resource.azurerm_kubernetes_cluster.role_based_access_control_enabled
    msg = "AKS clusters must have RBAC enabled"
}

# Validate node pool configuration
deny[msg] {
    terraform.resource.azurerm_kubernetes_cluster_node_pool
    not terraform.resource.azurerm_kubernetes_cluster_node_pool.enable_node_public_ip == false
    msg = "Node pools must not have public IPs"
}

# Enforce mandatory tags
deny[msg] {
    terraform.resource
    mandatory_tags := {"Environment", "ManagedBy", "Network"}
    resource_tags := {tag | resource.tags[tag]}
    missing_tags := mandatory_tags - resource_tags
    count(missing_tags) > 0
    msg = sprintf("Resource missing required tags: %v", [missing_tags])
}

# Validate monitoring configuration
deny[msg] {
    terraform.resource.azurerm_kubernetes_cluster
    not terraform.resource.azurerm_kubernetes_cluster.monitor_metrics_enabled
    msg = "AKS clusters must have monitoring metrics enabled"
}

# Enforce encryption at rest
deny[msg] {
    terraform.resource.azurerm_kubernetes_cluster
    not terraform.resource.azurerm_kubernetes_cluster.disk_encryption_set_id
    msg = "AKS clusters must use disk encryption"
}

# Network-specific validation rules
mainnet_rules[msg] {
    input.chain_id == "138"
    input.min_validator_count < 4
    msg := "Mainnet requires at least 4 validators"
}

mainnet_rules[msg] {
    input.chain_id == "138"
    not input.high_availability
    msg := "Mainnet deployment must have high availability enabled"
}

testnet_rules[msg] {
    input.chain_id == "2138"
    input.min_validator_count < 2
    msg := "Testnet requires at least 2 validators"
}

devnet_rules[msg] {
    input.chain_id == "1337"
    input.min_validator_count < 1
    msg := "Devnet requires at least 1 validator"
}

# Common validation rules
validate_network_config[msg] {
    not valid_chain_id(input.chain_id)
    msg := sprintf("Invalid chain ID: %v. Must be one of: 138 (mainnet), 2138 (testnet), or 1337 (devnet)", [input.chain_id])
}

validate_network_config[msg] {
    input.chain_id == "138"
    msg := mainnet_rules[_]
}

validate_network_config[msg] {
    input.chain_id == "2138"
    msg := testnet_rules[_]
}

validate_network_config[msg] {
    input.chain_id == "1337"
    msg := devnet_rules[_]
}

# Helper functions
valid_chain_id(id) {
    id == "138"
} {
    id == "2138"
} {
    id == "1337"
}

# Resource validation
validate_resources[msg] {
    input.chain_id == "138"  # Mainnet
    input.resources.limits.cpu < 2
    msg := "Mainnet nodes require at least 2 CPU cores"
}

validate_resources[msg] {
    input.chain_id == "138"  # Mainnet
    input.resources.limits.memory < 8589934592  # 8Gi in bytes
    msg := "Mainnet nodes require at least 8Gi memory"
}

validate_resources[msg] {
    input.chain_id == "2138"  # Testnet
    input.resources.limits.cpu < 1
    msg := "Testnet nodes require at least 1 CPU core"
}

validate_resources[msg] {
    input.chain_id == "2138"  # Testnet
    input.resources.limits.memory < 4294967296  # 4Gi in bytes
    msg := "Testnet nodes require at least 4Gi memory"
}

# Storage validation
validate_storage[msg] {
    input.chain_id == "138"  # Mainnet
    input.storage.size < 200
    msg := "Mainnet nodes require at least 200GB storage"
}

validate_storage[msg] {
    input.chain_id == "2138"  # Testnet
    input.storage.size < 100
    msg := "Testnet nodes require at least 100GB storage"
}

validate_storage[msg] {
    input.chain_id == "1337"  # Devnet
    input.storage.size < 20
    msg := "Devnet nodes require at least 20GB storage"
}

# Network policy validation
validate_network_policies[msg] {
    input.chain_id == "138"  # Mainnet
    not input.network_policies.enable_ingress_restriction
    msg := "Mainnet deployments must enable ingress restrictions"
}

validate_network_policies[msg] {
    input.chain_id == "138"  # Mainnet
    not input.network_policies.enable_egress_restriction
    msg := "Mainnet deployments must enable egress restrictions"
}

# Combined validation
deny[msg] {
    msg := validate_network_config[_]
} {
    msg := validate_resources[_]
} {
    msg := validate_storage[_]
} {
    msg := validate_network_policies[_]
}

package besu

import data.kubernetes
import data.terraform

# Default network parameters
networks = {
    "mainnet": {
        "chain_id": 138,
        "min_nodes": 7,
        "min_peers": 10,
        "required_cpu": 24,
        "required_memory": 32,
        "pod_security_level": "restricted",
        "allow_privileged": false,
        "require_https": true,
        "encryption_at_rest": true,
        "min_tls_version": "1.3",
        "network_policy": true
    },
    "testnet": {
        "chain_id": 2138,
        "min_nodes": 4,
        "min_peers": 5,
        "required_cpu": 8,
        "required_memory": 16,
        "pod_security_level": "baseline",
        "allow_privileged": false,
        "require_https": true,
        "encryption_at_rest": true,
        "min_tls_version": "1.2",
        "network_policy": true
    },
    "devnet": {
        "chain_id": 1337,
        "min_nodes": 1,
        "min_peers": 1,
        "required_cpu": 4,
        "required_memory": 8,
        "pod_security_level": "privileged",
        "allow_privileged": true,
        "require_https": false,
        "encryption_at_rest": false,
        "min_tls_version": "1.2",
        "network_policy": false
    }
}

# Validate network configuration
deny[msg] {
    network := input.network_type
    not networks[network]
    msg := sprintf("Invalid network type: %v. Must be one of: mainnet, testnet, devnet", [network])
}

# Validate minimum node count
deny[msg] {
    network := input.network_type
    count := input.node_count
    count < networks[network].min_nodes
    msg := sprintf("Node count %v is less than minimum required (%v) for %v", [count, networks[network].min_nodes, network])
}

# Validate required regions
deny[msg] {
    network := input.network_type
    region := input.region
    required := networks[network].requiredRegions
    not array_contains(required, region)
    msg := sprintf("Region %v is not in required regions %v for %v", [region, required, network])
}

# Validate VM families
deny[msg] {
    network := input.network_type
    vm_family := input.vm_family
    allowed := networks[network].vmFamilies
    not array_contains(allowed, vm_family)
    msg := sprintf("VM family %v is not in allowed families %v for %v", [vm_family, allowed, network])
}

# Helper functions
array_contains(arr, elem) {
    arr[_] = elem
}

# Validate chain ID matches network type
deny[msg] {
    network := input.network_type
    chain_id := input.chain_id
    chain_id != networks[network].chainId
    msg := sprintf("Chain ID %v does not match expected ID %v for %v", [chain_id, networks[network].chainId, network])
}

# Network-specific storage requirements
storage_requirements = {
    "mainnet": {
        "validator": "512Gi",
        "bootnode": "1Ti",
        "rpc": "2Ti",
        "storageClass": "premium-ssd"
    },
    "testnet": {
        "validator": "256Gi",
        "bootnode": "512Gi",
        "rpc": "512Gi",
        "storageClass": "standard-ssd"
    },
    "devnet": {
        "validator": "128Gi",
        "bootnode": "128Gi",
        "rpc": "128Gi",
        "storageClass": "standard-ssd"
    }
}

# Validate storage configuration
deny[msg] {
    network := input.network_type
    node_type := input.node_type
    storage := input.storage
    required := storage_requirements[network][node_type]
    storage < required
    msg := sprintf("Storage size %v is less than required %v for %v nodes in %v", [storage, required, node_type, network])
}

# Validate storage class
deny[msg] {
    network := input.network_type
    storage_class := input.storage_class
    required := storage_requirements[network].storageClass
    storage_class != required
    msg := sprintf("Storage class %v does not match required %v for %v", [storage_class, required, network])
}

# Kubernetes policy rules
deny[msg] {
    input.kind == "Pod"
    input.metadata.namespace == "besu"
    network_type := get_network_type(input)
    not valid_pod_security(network_type, input)
    msg := sprintf("Pod security configuration does not meet %s requirements", [network_type])
}

deny[msg] {
    input.kind == "Service"
    input.metadata.namespace == "besu"
    network_type := get_network_type(input)
    not valid_service_config(network_type, input)
    msg := sprintf("Service configuration does not meet %s requirements", [network_type])
}

deny[msg] {
    input.kind == "NetworkPolicy"
    input.metadata.namespace == "besu"
    network_type := get_network_type(input)
    networks[network_type].network_policy
    not valid_network_policy(network_type, input)
    msg := sprintf("NetworkPolicy does not meet %s requirements", [network_type])
}

# Terraform policy rules
deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_kubernetes_cluster"
    network_type := get_network_type_from_tags(resource)
    not valid_aks_config(network_type, resource)
    msg := sprintf("AKS cluster configuration does not meet %s requirements", [network_type])
}

deny[msg] {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "azurerm_key_vault"
    network_type := get_network_type_from_tags(resource)
    not valid_key_vault_config(network_type, resource)
    msg := sprintf("Key Vault configuration does not meet %s requirements", [network_type])
}

# Helper functions
get_network_type(resource) = network_type {
    chain_id := resource.metadata.labels["network.besu.hyperledger.org/chainId"]
    network_type := [name | networks[name].chain_id == chain_id][0]
}

get_network_type_from_tags(resource) = network_type {
    network_type := resource.values.tags.network_type
}

valid_pod_security(network_type, pod) {
    security_level := networks[network_type].pod_security_level
    pod.spec.securityContext.runAsNonRoot == true
    security_level == "restricted"
}

valid_pod_security(network_type, pod) {
    security_level := networks[network_type].pod_security_level
    security_level == "baseline"
}

valid_service_config(network_type, svc) {
    require_https := networks[network_type].require_https
    require_https == false
} {
    require_https := networks[network_type].require_https
    require_https == true
    svc.spec.ports[_].name == "https"
}

valid_network_policy(network_type, policy) {
    chain_id := networks[network_type].chain_id
    policy.spec.podSelector.matchLabels["network.besu.hyperledger.org/chainId"] == sprintf("%d", [chain_id])
    count(policy.spec.ingress) > 0
    count(policy.spec.egress) > 0
}

valid_aks_config(network_type, cluster) {
    min_nodes := networks[network_type].min_nodes
    required_cpu := networks[network_type].required_cpu
    required_memory := networks[network_type].required_memory
    
    to_number(cluster.values.default_node_pool[0].node_count) >= min_nodes
    to_number(cluster.values.default_node_pool[0].vm_size_cpu) >= required_cpu
    to_number(cluster.values.default_node_pool[0].vm_size_memory_gb) >= required_memory
}

valid_key_vault_config(network_type, vault) {
    encryption := networks[network_type].encryption_at_rest
    encryption == false
} {
    encryption := networks[network_type].encryption_at_rest
    encryption == true
    vault.values.sku_name == "premium"
    vault.values.enabled_for_disk_encryption == true
    vault.values.purge_protection_enabled == true
}