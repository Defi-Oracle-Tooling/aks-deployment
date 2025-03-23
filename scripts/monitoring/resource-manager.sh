#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/../deployment/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE=${NAMESPACE:-"besu"}
CPU_THRESHOLD=${CPU_THRESHOLD:-"80"}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-"85"}

# Function to check resource usage
check_resources() {
    local deployment=$1
    
    # Get CPU usage
    local cpu_usage=$(kubectl top pod -n "$NAMESPACE" -l app="$deployment" --use-protocol-buffers | 
        tail -n +2 | 
        awk '{print $3}' | 
        sed 's/[^0-9]*//g')

    # Get memory usage
    local memory_usage=$(kubectl top pod -n "$NAMESPACE" -l app="$deployment" --use-protocol-buffers | 
        tail -n +2 | 
        awk '{print $4}' | 
        sed 's/[^0-9]*//g')

    # Check thresholds and scale if needed
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ] || [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
        echo "Resource threshold exceeded for $deployment"
        scale_deployment "$deployment"
    fi
}

# Function to scale deployment
scale_deployment() {
    local deployment=$1
    local current_replicas=$(kubectl get deployment -n "$NAMESPACE" "$deployment" -o jsonpath='{.spec.replicas}')
    local new_replicas=$((current_replicas + 1))

    echo "Scaling $deployment from $current_replicas to $new_replicas replicas"
    kubectl scale deployment -n "$NAMESPACE" "$deployment" --replicas="$new_replicas"
    log_audit "deployment_scaled" "Scaled $deployment to $new_replicas replicas"
}

# Check all deployments
kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' | 
tr ' ' '\n' | 
while read -r deployment; do
    check_resources "$deployment"
done
