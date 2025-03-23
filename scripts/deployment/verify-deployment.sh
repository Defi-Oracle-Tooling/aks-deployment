#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Source the deployment utilities (includes configuration loading)
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Use the get_config_value function from the utility
MIN_NODES=$(get_config_value "environments.mainnet.minNodes")
echo "Minimum nodes for mainnet: $MIN_NODES"

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"
REGIONS_FILE=$(get_config_value "cloud_providers.azure.regions")
VM_FAMILIES_FILE=$(get_config_value "cloud_providers.azure.vm_families")
NETWORKS_FILE=$(get_config_value "cloud_providers.azure.networks")
STORAGE_FILE=$(get_config_value "cloud_providers.azure.storage")

# Parse command line arguments
usage() {
    echo "Usage: $0 [--network <mainnet|testnet|devnet>] [--region <region-name>]"
    echo "Default network: mainnet"
    exit 1
}

NETWORK="mainnet"
REGION=""

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
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Load network-specific configurations
case $NETWORK in
    "mainnet")
        CHAIN_ID=138
        MIN_NODES=7
        MIN_PEERS=10
        REQUIRED_CPU=24
        REQUIRED_MEMORY=32
        ;;
    "testnet")
        CHAIN_ID=2138
        MIN_NODES=4
        MIN_PEERS=5
        REQUIRED_CPU=8
        REQUIRED_MEMORY=16
        ;;
    "devnet")
        CHAIN_ID=1337
        MIN_NODES=1
        MIN_PEERS=1
        REQUIRED_CPU=4
        REQUIRED_MEMORY=8
        ;;
    *)
        echo "Error: Invalid network type"
        exit 1
        ;;
esac

# Verify network prerequisites
verify_network_prerequisites() {
    local region=$1
    echo "Verifying network prerequisites for $NETWORK in $region..."

    # Check AKS cluster status
    if ! az aks show --resource-group "besu-network-${region}" --name "besu-aks-${region}" --query "provisioningState" -o tsv | grep -q "Succeeded"; then
        echo "❌ AKS cluster verification failed in $region"
        return 1
    fi

    # Check node count
    local node_count=$(kubectl get nodes --selector=kubernetes.io/role=agent -o name | wc -l)
    if [ "$node_count" -lt "$MIN_NODES" ]; then
        echo "❌ Insufficient nodes in $region: found $node_count, required $MIN_NODES"
        return 1
    fi

    # Verify node resources
    local cpu_check=$(kubectl get nodes -o json | jq -r '.items[].status.capacity.cpu' | awk "{ sum += \$1 } END { print sum >= $REQUIRED_CPU }")
    local memory_check=$(kubectl get nodes -o json | jq -r '.items[].status.capacity.memory' | sed 's/Ki//' | awk "{ sum += \$1 } END { print sum >= ($REQUIRED_MEMORY * 1024 * 1024) }")
    
    if [[ "$cpu_check" != "1" || "$memory_check" != "1" ]]; then
        echo "❌ Insufficient resources in $region"
        return 1
    fi

    echo "✅ Network prerequisites verified in $region"
    return 0
}

# Verify Besu node deployment
verify_besu_deployment() {
    local region=$1
    echo "Verifying Besu deployment for $NETWORK in $region..."

    # Check pod status
    local running_pods=$(kubectl get pods -n besu -l "network.besu.hyperledger.org/chainId=$CHAIN_ID" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    if [ "$running_pods" -lt "$MIN_NODES" ]; then
        echo "❌ Not all Besu pods are running in $region"
        return 1
    fi

    # Check peer connections
    for pod in $(kubectl get pods -n besu -l "network.besu.hyperledger.org/chainId=$CHAIN_ID" -o jsonpath='{.items[*].metadata.name}'); do
        local peer_count=$(kubectl exec -n besu $pod -- curl -s localhost:9545/metrics | grep besu_network_peer_count | awk '{print $2}')
        if [ "$peer_count" -lt "$MIN_PEERS" ]; then
            echo "❌ Insufficient peer connections for pod $pod in $region: $peer_count < $MIN_PEERS"
            return 1
        fi
    done

    # Verify chain ID
    for pod in $(kubectl get pods -n besu -l "network.besu.hyperledger.org/chainId=$CHAIN_ID" -o jsonpath='{.items[*].metadata.name}'); do
        local chain_id=$(kubectl exec -n besu $pod -- curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8545 | jq -r '.result' | sed 's/0x//')
        if [ "$chain_id" != "$CHAIN_ID" ]; then
            echo "❌ Chain ID mismatch in $region: expected $CHAIN_ID, got $chain_id"
            return 1
        fi
    done

    echo "✅ Besu deployment verified in $region"
    return 0
}

# Verify monitoring setup
verify_monitoring() {
    local region=$1
    echo "Verifying monitoring setup for $NETWORK in $region..."

    # Check Prometheus
    if ! kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        echo "❌ Prometheus is not running in $region"
        return 1
    fi

    # Check Grafana
    if ! kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        echo "❌ Grafana is not running in $region"
        return 1
    fi

    # Verify metrics collection
    if ! curl -s "http://prometheus.monitoring:9090/api/v1/query?query=up{job=\"besu-${NETWORK}\"}" | jq -e '.data.result[0].value[1] == "1"' > /dev/null; then
        echo "❌ Metrics collection not working in $region"
        return 1
    fi

    echo "✅ Monitoring setup verified in $region"
    return 0
}

# Main verification process
if [ -n "$REGION" ]; then
    # Verify single region
    echo "🔍 Starting verification for $NETWORK in $REGION..."
    verify_network_prerequisites "$REGION" && \
    verify_besu_deployment "$REGION" && \
    verify_monitoring "$REGION"
else
    # Verify all regions
    echo "🔍 Starting verification for $NETWORK in all regions..."
    for region in $(az aks list --query "[].location" -o tsv | sort -u); do
        echo "Verifying region: $region"
        verify_network_prerequisites "$region" && \
        verify_besu_deployment "$region" && \
        verify_monitoring "$region" || \
        echo "❌ Verification failed in $region"
    done
fi