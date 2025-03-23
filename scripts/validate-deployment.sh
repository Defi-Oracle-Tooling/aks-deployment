#!/bin/bash

# Check cluster health
check_cluster_health() {
    local cluster_name=$1
    local resource_group=$2

    echo "Checking cluster health: $cluster_name"
    
    # Check node status
    kubectl get nodes -o wide
    if [ $? -ne 0 ]; then
        echo "Error: Node check failed"
        return 1
    }

    # Check core components
    kubectl get pods -n kube-system
    if [ $? -ne 0 ]; then
        echo "Error: Core components check failed"
        return 1
    }

    # Check monitoring
    kubectl get pods -n monitoring
    if [ $? -ne 0 ]; then
        echo "Error: Monitoring check failed"
        return 1
    }

    return 0
}

# Main validation process
main() {
    local cluster_name=$1
    local resource_group=$2

    # Connect to cluster
    az aks get-credentials --name $cluster_name --resource-group $resource_group

    # Run health checks
    check_cluster_health $cluster_name $resource_group
    if [ $? -ne 0 ]; then
        echo "Validation failed for cluster: $cluster_name"
        exit 1
    }

    echo "Validation completed successfully"
}

# Execute main function with arguments
main "$@"
