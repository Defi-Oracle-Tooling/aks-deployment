package kubernetes

import data.common

# Container security context validations
container = input.spec.containers[_]

container_denied[msg] {
    container
    not container.securityContext.readOnlyRootFilesystem
    msg = sprintf("Container %v must have a read-only root filesystem", [container.name])
}

container_denied[msg] {
    container
    not container.securityContext.allowPrivilegeEscalation == false
    msg = sprintf("Container %v must not allow privilege escalation", [container.name])
}

# Pod security validations
pod_denied[msg] {
    input.kind == "Pod"
    not input.spec.securityContext.runAsNonRoot
    msg = "Pod must run as non-root"
}

pod_denied[msg] {
    input.kind == "Pod"
    not input.spec.securityContext.seccompProfile.type == "RuntimeDefault"
    msg = "Pod must use RuntimeDefault seccomp profile"
}

# Network policy validations
networkpolicy_required[msg] {
    input.kind == "NetworkPolicy"
    not input.spec.policyTypes[_] == "Egress"
    msg = "NetworkPolicy must specify egress rules"
}

networkpolicy_required[msg] {
    input.kind == "NetworkPolicy"
    not input.spec.policyTypes[_] == "Ingress"
    msg = "NetworkPolicy must specify ingress rules"
}

# Volume mount validations
volume_denied[msg] {
    input.kind == "Pod"
    volume := input.spec.volumes[_]
    volume.hostPath
    msg = sprintf("Pod %v must not use hostPath volumes", [input.metadata.name])
}

# Service account validations
serviceaccount_denied[msg] {
    input.kind == "ServiceAccount"
    not input.automountServiceAccountToken == false
    msg = sprintf("ServiceAccount %v must not auto-mount API credentials", [input.metadata.name])
}

# Role and ClusterRole validations
role_denied[msg] {
    input.kind == "Role"
    some i
    input.rules[i].verbs[_] == "*"
    msg = sprintf("Role %v must not use wildcard verbs", [input.metadata.name])
}

# Namespace validations
namespace_denied[msg] {
    input.kind == "Namespace"
    not input.metadata.labels.name
    msg = sprintf("Namespace %v must have a name label", [input.metadata.name])
}

# Pod disruption budget validations
pdb_required[msg] {
    input.kind == "Deployment"
    not pod_disruption_budget_exists(input.metadata.name)
    msg = sprintf("Deployment %v must have a PodDisruptionBudget", [input.metadata.name])
}

pod_disruption_budget_exists(name) {
    some pdb
    input_pdbs[pdb].spec.selector.matchLabels.app == name
}

# Resource quota validations
quota_required[msg] {
    input.kind == "Namespace"
    not resource_quota_exists(input.metadata.name)
    msg = sprintf("Namespace %v must have a ResourceQuota", [input.metadata.name])
}

resource_quota_exists(namespace) {
    some quota
    input_quotas[quota].metadata.namespace == namespace
}

# Custom validations for Besu nodes
besu_node_validations[msg] {
    input.kind == "StatefulSet"
    input.metadata.labels.app == "besu-validator"
    not input.spec.template.spec.containers[_].resources.limits.cpu
    msg = "Besu validator nodes must have CPU limits defined"
}

besu_node_validations[msg] {
    input.kind == "StatefulSet"
    input.metadata.labels.app == "besu-validator"
    not input.spec.template.spec.containers[_].resources.limits.memory
    msg = "Besu validator nodes must have memory limits defined"
}

# Network-specific validations
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    not input.spec.securityContext.runAsNonRoot

    msg := "Mainnet pods must run as non-root user"
}

deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    not input.spec.securityContext.readOnlyRootFilesystem

    msg := "Mainnet pods must have read-only root filesystem"
}

deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    container := input.spec.containers[_]
    not container.resources.limits

    msg := sprintf("Mainnet container '%v' must have resource limits", [container.name])
}

# Testnet specific rules - less strict
warn[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "testnet"
    not input.spec.securityContext.runAsNonRoot

    msg := "Warning: Consider running testnet pods as non-root"
}

# Common validations across all networks
deny[msg] {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.securityContext.allowPrivilegeEscalation == false

    msg := sprintf("Container '%v' must not allow privilege escalation", [container.name])
}

# Network-specific resource quotas
deny[msg] {
    input.kind == "ResourceQuota"
    input.metadata.labels.network_type == "mainnet"
    not input.spec.hard["limits.cpu"]

    msg := "Mainnet namespaces must have CPU limits defined"
}

# Network-specific pod security rules
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    container := input.spec.containers[_]
    not container.securityContext.runAsNonRoot

    msg := sprintf("Mainnet pods must run as non-root user: %v", [container.name])
}

# Network-specific resource requirements
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    container := input.spec.containers[_]
    not container.resources.limits

    msg := sprintf("Mainnet containers must have resource limits defined: %v", [container.name])
}

# Network-specific liveness probe requirements
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    container := input.spec.containers[_]
    not container.livenessProbe

    msg := sprintf("Mainnet containers must have liveness probes: %v", [container.name])
}

# Network-specific network policy requirements
deny[msg] {
    input.kind == "NetworkPolicy"
    input.metadata.labels.network_type == "mainnet"
    not input.spec.ingress

    msg := "Mainnet network policies must explicitly define ingress rules"
}

# Testnet-specific rules - less strict
warn[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "testnet"
    container := input.spec.containers[_]
    not container.securityContext.runAsNonRoot

    msg := sprintf("Warning: Consider running testnet containers as non-root: %v", [container.name])
}

# Network-specific service account requirements
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    not input.spec.serviceAccountName

    msg := "Mainnet pods must use explicit service accounts"
}

# Network-specific readiness probe requirements
deny[msg] {
    input.kind == "Pod"
    input.metadata.labels.network_type == "mainnet"
    container := input.spec.containers[_]
    not container.readinessProbe

    msg := sprintf("Mainnet containers must have readiness probes: %v", [container.name])
}

# Aggregate all validations
deny[msg] {
    msg := container_denied[_]
}

deny[msg] {
    msg := pod_denied[_]
}

deny[msg] {
    msg := networkpolicy_required[_]
}

deny[msg] {
    msg := volume_denied[_]
}

deny[msg] {
    msg := serviceaccount_denied[_]
}

deny[msg] {
    msg := role_denied[_]
}

deny[msg] {
    msg := namespace_denied[_]
}

deny[msg] {
    msg := pdb_required[_]
}

deny[msg] {
    msg := quota_required[_]
}

deny[msg] {
    msg := besu_node_validations[_]
}