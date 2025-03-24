#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/../deployment/deployment-utils.sh"

# Initialize logging
setup_logging

# Constants
MIN_NODES=1
MAX_NODES=100

usage() {
    echo "Usage: $0 --resource-group <rg-name> --cluster-name <cluster-name> --node-count <count> [--node-type <type>]"
    echo "Node types: validator, bootnode, rpc (default: validator)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift
            shift
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift
            shift
            ;;
        --node-count)
            NODE_COUNT="$2"
            shift
            shift
            ;;
        --node-type)
            NODE_TYPE="$2"
            shift
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# Set default node type
NODE_TYPE=${NODE_TYPE:-validator}

# Validate inputs
if [[ -z "$RESOURCE_GROUP" || -z "$CLUSTER_NAME" || -z "$NODE_COUNT" ]]; then
    usage
fi

if ! [[ "$NODE_COUNT" =~ ^[0-9]+$ ]] || \
   [[ "$NODE_COUNT" -lt "$MIN_NODES" ]] || \
   [[ "$NODE_COUNT" -gt "$MAX_NODES" ]]; then
    echo "Error: Node count must be between $MIN_NODES and $MAX_NODES"
    exit 1
fi

# Scale node pool
scale_node_pool() {
    echo "Scaling ${NODE_TYPE} node pool to ${NODE_COUNT} nodes..."
    
    # Get current node count for comparison
    local current_count=$(az aks nodepool show \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$CLUSTER_NAME" \
        --name "${NODE_TYPE}pool" \
        --query "count" -o tsv)

    # Scale the node pool
    if ! az aks nodepool scale \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$CLUSTER_NAME" \
        --name "${NODE_TYPE}pool" \
        --node-count "$NODE_COUNT"; then
        handle_error 500 "Failed to scale node pool"
        exit 1
    fi

    log_audit "node_pool_scaled" "Scaled ${NODE_TYPE} pool from ${current_count} to ${NODE_COUNT} nodes"
    echo "✅ Node pool scaling completed successfully"
}

scale_node_pool
