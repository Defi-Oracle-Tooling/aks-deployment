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