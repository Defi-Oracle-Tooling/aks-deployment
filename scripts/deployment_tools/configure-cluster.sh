#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/../deployment/deployment-utils.sh"

# Initialize logging 
setup_logging

# Constants
SUPPORTED_NETWORKS=("mainnet" "testnet" "devnet")

usage() {
    echo "Usage: $0 --network <network-type> --region <region> [--monitoring] [--security]"
    echo "Supported networks: ${SUPPORTED_NETWORKS[*]}"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --network)
            NETWORK="$2"
            shift
            shift
            ;;
        --region)
            REGION="$2"
            shift
            shift
            ;;
        --monitoring)
            SETUP_MONITORING=true
            shift
            ;;
        --security)
            SETUP_SECURITY=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# Validate inputs
if [[ ! " ${SUPPORTED_NETWORKS[@]} " =~ " ${NETWORK} " ]]; then
    echo "Error: Invalid network type: ${NETWORK}"
    usage
fi

# Configure cluster
configure_cluster() {
    echo "Configuring cluster in ${REGION} for ${NETWORK}..."

    # Basic cluster setup
    if ! az aks get-credentials --resource-group "${RESOURCE_GROUP_PREFIX}-${REGION}" \
        --name "${AKS_CLUSTER_PREFIX}-${REGION}" --overwrite-existing; then
        handle_error 400 "Failed to get cluster credentials"
        exit 1
    fi

    # Setup monitoring if requested
    if [[ "$SETUP_MONITORING" == true ]]; then
        echo "Setting up monitoring..."
        "${PROJECT_ROOT}/scripts/deployment/setup-monitoring.sh" --network "$NETWORK" --region "$REGION"
    fi

    # Setup security if requested 
    if [[ "$SETUP_SECURITY" == true ]]; then
        echo "Setting up security..."
        "${PROJECT_ROOT}/scripts/deployment/harden-security.sh" --network "$NETWORK" --region "$REGION"
    fi

    log_audit "cluster_configured" "Cluster configuration completed for ${NETWORK} in ${REGION}"
}

configure_cluster
