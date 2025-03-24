#!/bin/bash

# Source common utilities
source "$(dirname "$0")/config-manager.sh"
source "$(dirname "$0")/log-manager.sh"

# Constants
HEALTH_CHECK_TIMEOUT=300

# Check AKS cluster health
check_cluster_health() {
    local resource_group=$1
    local cluster_name=$2

    log_message "INFO" "Checking cluster health for $cluster_name in $resource_group"

    if ! az aks show \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --query "provisioningState" -o tsv | grep -q "Succeeded"; then
        log_error 50 "Cluster $cluster_name health check failed"
        return 1
    fi
    return 0
}

# Check node health
check_node_health() {
    local node_count=$1
    local min_nodes=$2

    log_message "INFO" "Checking node health (minimum required: $min_nodes)"

    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ $ready_nodes -lt $min_nodes ]]; then
        log_error 51 "Insufficient healthy nodes: $ready_nodes / $min_nodes"
        return 1
    fi
    return 0
}

# Check pod health
check_pod_health() {
    local namespace=$1
    local label_selector=$2
    local min_pods=$3

    log_message "INFO" "Checking pod health in namespace $namespace"

    local running_pods=$(kubectl get pods -n "$namespace" -l "$label_selector" --field-selector status.phase=Running --no-headers | wc -l)
    if [[ $running_pods -lt $min_pods ]]; then
        log_error 52 "Insufficient running pods: $running_pods / $min_pods"
        return 1
    fi
    return 0
}

# Comprehensive health check
verify_health() {
    local resource_group=$1
    local cluster_name=$2
    local namespace=$3
    local min_nodes=$4
    local min_pods=$5
    local label_selector=${6:-"app.kubernetes.io/part-of=besu"}

    check_cluster_health "$resource_group" "$cluster_name" && \
    check_node_health "$min_nodes" "$min_nodes" && \
    check_pod_health "$namespace" "$label_selector" "$min_pods"

    return $?
}
