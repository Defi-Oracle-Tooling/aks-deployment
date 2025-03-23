#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/../deployment/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE=${NAMESPACE:-"besu"}
TEST_DURATION=${TEST_DURATION:-"300"}  # 5 minutes default
RPS=${RPS:-"100"}  # Requests per second

# Install hey if not present
if ! command -v hey &> /dev/null; then
    echo "Installing hey load testing tool..."
    go get -u github.com/rakyll/hey
fi

# Get namespace from configuration
NAMESPACE=$(get_namespace "blockchain")
TEST_NAMESPACE=$(get_namespace "testing")

# Function to run load test
run_load_test() {
    local endpoint=$1
    local duration=$2
    local rps=$3

    echo "Running load test against $endpoint..."
    echo "Duration: ${duration}s, Rate: $rps requests/second"

    hey -z "${duration}s" -q "$rps" -m POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint"
}

# Get endpoints
ENDPOINTS=$(kubectl get svc -n "$NAMESPACE" -l app=besu-rpc -o jsonpath='{.items[*].status.loadBalancer.ingress[*].ip}')

# Run tests
for endpoint in $ENDPOINTS; do
    run_load_test "http://${endpoint}:8545" "$TEST_DURATION" "$RPS"
done
