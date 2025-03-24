#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/../deployment/deployment-utils.sh"

# Initialize logging
setup_logging

# Constants
SUPPORTED_NETWORKS=("mainnet" "testnet" "devnet")

usage() {
    echo "Usage: $0 --network <network-type> --region <region> [--advanced]"
    echo "Supported networks: ${SUPPORTED_NETWORKS[*]}"
    exit 1
}

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
        --advanced)
            ADVANCED_CONFIG=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# Validate network type
if [[ ! " ${SUPPORTED_NETWORKS[@]} " =~ " ${NETWORK} " ]]; then
    echo "Error: Invalid network type: ${NETWORK}"
    usage
fi

# Configure network policies and rules
configure_network() {
    echo "Configuring network for ${NETWORK} in ${REGION}..."

    # Apply base network policies
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: besu-${NETWORK}-base
  namespace: besu
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: besu-network
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/part-of: besu-network
    ports:
    - protocol: TCP
      port: 30303
    - protocol: UDP
      port: 30303
EOF

    # Apply advanced configuration if requested
    if [[ "$ADVANCED_CONFIG" == true ]]; then
        # Apply additional security groups and rules
        az network nsg rule create \
            --resource-group "${RESOURCE_GROUP_PREFIX}-${REGION}" \
            --nsg-name "${AKS_CLUSTER_PREFIX}-${REGION}-nsg" \
            --name "AllowBesuP2P" \
            --priority 100 \
            --source-address-prefixes "*" \
            --source-port-ranges "*" \
            --destination-port-ranges 30303 \
            --protocol "Tcp"
    fi

    log_audit "network_configured" "Network configuration completed for ${NETWORK} in ${REGION}"
    echo "✅ Network configuration completed successfully"
}

configure_network
