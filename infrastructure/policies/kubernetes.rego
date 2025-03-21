package kubernetes

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