#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Source the deployment utilities (includes configuration loading)
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Use the get_config_value function from the utility
RESOURCE_GROUP_PREFIX=$(get_config_value "common.resource_group_prefix")
echo "Resource group prefix: $RESOURCE_GROUP_PREFIX"

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"
REGIONS_FILE=$(get_config_value "cloud_providers.azure.regions")
VM_FAMILIES_FILE=$(get_config_value "cloud_providers.azure.vm_families")
NETWORKS_FILE=$(get_config_value "cloud_providers.azure.networks")
STORAGE_FILE=$(get_config_value "cloud_providers.azure.storage")

# Log files for rollback states
ROLLBACK_LOG="rollback.log"

# Source the deployment-utils.sh if not already sourced
if ! command -v cleanup_resources &> /dev/null; then
    source "$(dirname "$0")/deployment/deployment-utils.sh"
fi

# Function to rollback deployment
rollback_deployment() {
    local resource_group=$1
    local resource_name=$2
    local resource_type=$3
    local namespace=$4
    echo "Rolling back deployment for $resource_name in $resource_group..." | tee -a $ROLLBACK_LOG
    cleanup_resources $resource_group $resource_name $resource_type $namespace
    echo "Rollback completed for $resource_name in $resource_group" | tee -a $ROLLBACK_LOG
}

# Set the Azure subscription
az account set --subscription "$(get_config_value "azure.subscription_id")"

# Read resources from Azureresources (1).csv
while IFS=, read -r name type resource_group location subscription namespace; do
    if [[ "$name" != "NAME" ]]; then
        # Trim quotes and spaces from type
        type=$(echo "$type" | tr -d '"' | xargs)
        case $type in
            "Kubernetes service")
                namespace="Microsoft.ContainerService"
                resource_type="managedClusters"
                ;;
            "Managed Identity")
                namespace="Microsoft.ManagedIdentity"
                resource_type="userAssignedIdentities"
                ;;
            "Load balancer")
                namespace="Microsoft.Network"
                resource_type="loadBalancers"
                ;;
            "Network security group")
                namespace="Microsoft.Network"
                resource_type="networkSecurityGroups"
                ;;
            "Public IP address")
                namespace="Microsoft.Network"
                resource_type="publicIPAddresses"
                ;;
            "Virtual network")
                namespace="Microsoft.Network"
                resource_type="virtualNetworks"
                ;;
            "Virtual machine scale set")
                namespace="Microsoft.Compute"
                resource_type="virtualMachineScaleSets"
                ;;
            *)
                echo "Unknown resource type: $type"
                continue
                ;;
        esac
        rollback_deployment "$resource_group" "$name" "$resource_type" "$namespace"
    fi
done < /Users/pandora/VS_Code_Projects/aks-deployment-1/Azureresources\ \(1\).csv

# Notify on completion
if [[ -s $ROLLBACK_LOG ]]; then
    echo "✅ Rollback completed. Check $ROLLBACK_LOG." | tee -a $ROLLBACK_LOG
fi
