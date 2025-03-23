#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/deployment/deployment-utils.sh"

# Initialize logging
setup_logging

# Constants
MIN_READY_NODES=3
VERIFICATION_TIMEOUT=300

# Function to verify node status
verify_node_status() {
    local region=$1
    local cluster_name="besu-aks-${region}"
    local resource_group="besu-network-${region}"

    echo "Verifying node status in ${cluster_name}..."

    # Get node count and status
    local ready_nodes=$(kubectl get nodes \
        --no-headers \
        -o custom-columns=":status.conditions[?(@.type=='Ready')].status" \
        | grep -c "True")

    if [ "$ready_nodes" -lt "$MIN_READY_NODES" ]; then
        handle_error 100 "Insufficient ready nodes: ${ready_nodes}/${MIN_READY_NODES}"
        return 1
    fi

    # Check node resources
    local nodes_with_issues=$(kubectl get nodes -o json | jq -r '
        .items[] | select(
            .status.conditions[] | select(
                .type == "MemoryPressure" or 
                .type == "DiskPressure" or 
                .type == "PIDPressure"
            ).status == "True"
        ).metadata.name')

    if [ -n "$nodes_with_issues" ]; then
        handle_error 101 "Nodes with resource pressure: ${nodes_with_issues}"
        return 1
    fi

    echo "✅ Node verification completed successfully"
    return 0
}

# Main verification process
main() {
    local regions=$(jq -r '.regions[].name' "$REGIONS_FILE")

    for region in $regions; do
        verify_node_status "$region"
    done
}

# Execute main function
main "$@"
