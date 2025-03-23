#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/../deployment/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE=${NAMESPACE:-"besu"}
MAX_AGE_DAYS=${MAX_AGE_DAYS:-"7"}

# Function to perform maintenance tasks
perform_maintenance() {
    echo "Starting cluster maintenance tasks..."

    # Clean up old pods
    echo "Cleaning up completed pods older than $MAX_AGE_DAYS days..."
    kubectl get pods --all-namespaces -o json | jq \
        ".items[] | select(.status.phase == \"Succeeded\") | 
        select(.status.startTime | fromdate | now - . > ${MAX_AGE_DAYS}*86400) |
        {namespace:.metadata.namespace, name:.metadata.name}" | \
        jq -r '[.namespace,.name] | @tsv' | \
        while read -r namespace name; do
            kubectl delete pod -n "$namespace" "$name"
        done

    # Clean up stale configmaps
    echo "Cleaning up unused configmaps..."
    kubectl get configmaps --all-namespaces -o json | jq \
        '.items[] | select(.metadata.ownerReferences == null)' | \
        jq -r '[.metadata.namespace,.metadata.name] | @tsv' | \
        while read -r namespace name; do
            kubectl delete configmap -n "$namespace" "$name" --ignore-not-found
        done

    # Update node taints and labels
    echo "Updating node maintenance labels..."
    kubectl get nodes -o name | while read -r node; do
        kubectl label --overwrite "$node" maintenance-check="$(date +%Y%m%d)"
    done

    echo "Maintenance tasks completed"
    log_audit "maintenance_completed" "Cluster maintenance tasks completed successfully"
}

# Execute maintenance
perform_maintenance
