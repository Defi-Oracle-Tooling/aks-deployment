#!/bin/bash

# Set project root and config file path
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_FILE="${PROJECT_ROOT}/config/dynamic_config.json"

# Ensure configuration file is available
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Function to query a value from the configuration file
# Usage: get_config_value "cloud_providers.azure.regions"
get_config_value() {
    local key="$1"
    jq -r ".$key" "$CONFIG_FILE"
}

# Example: load Azure regions into a variable
AZURE_REGIONS=$(get_config_value "cloud_providers.azure.regions")
echo "Azure regions: $AZURE_REGIONS"

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"
REGIONS_FILE=$(jq -r '.cloud_providers.azure.regions' "$CONFIG_PATHS_FILE")
VM_FAMILIES_FILE=$(jq -r '.cloud_providers.azure.vm_families' "$CONFIG_PATHS_FILE")
NETWORKS_FILE=$(jq -r '.cloud_providers.azure.networks' "$CONFIG_PATHS_FILE")
STORAGE_FILE=$(jq -r '.cloud_providers.azure.storage' "$CONFIG_PATHS_FILE")

# Constants for logging
LOG_DIR="/var/log/besu"
DEPLOYMENT_LOG="${LOG_DIR}/deployment.log"
ERROR_LOG="${LOG_DIR}/error.log"
AUDIT_LOG="${LOG_DIR}/audit.log"

# Initialize logging
setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${DEPLOYMENT_LOG}" "${ERROR_LOG}" "${AUDIT_LOG}"
}

# Enhanced error handling
handle_error() {
    local error_code=$1
    local error_message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Log structured error data
    echo "{\"timestamp\":\"${timestamp}\",\"error_code\":${error_code},\"message\":\"${error_message}\"}" >> "${ERROR_LOG}"
    
    # Send alert if critical
    if [[ ${error_code} -gt 30 ]]; then
        trigger_alert "CRITICAL" "${error_message}"
    fi
}

# Metrics collection
collect_metrics() {
    local region=$1
    local node_type=$2
    
    # Collect node metrics
    local metrics=$(az monitor metrics list \
        --resource "$(get_config_value "aks_cluster_prefix")-${region}" \
        --resource-type "Microsoft.ContainerService/managedClusters" \
        --metric "node_cpu_usage_percentage" "node_memory_working_set_percentage" \
        --output json)
    
    echo "${metrics}" >> "${LOG_DIR}/metrics/${region}_${node_type}.json"
}

# Health check function
check_node_health() {
    local region=$1
    local node_type=$2
    
    # Check node status
    local status=$(az aks show \
        --resource-group "$(get_config_value "resource_group_prefix")-${region}" \
        --name "$(get_config_value "aks_cluster_prefix")-${region}" \
        --query "agentPoolProfiles[?name=='${node_type}'].provisioningState" \
        --output tsv)
    
    if [[ "${status}" != "Succeeded" ]]; then
        handle_error 40 "Node health check failed for ${node_type} in ${region}"
        return 1
    fi
    return 0
}

# Audit logging
log_audit() {
    local action=$1
    local details=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local user=$(az account show --query user.name -o tsv)
    
    echo "{\"timestamp\":\"${timestamp}\",\"user\":\"${user}\",\"action\":\"${action}\",\"details\":\"${details}\"}" >> "${AUDIT_LOG}"
}

# Performance monitoring
monitor_performance() {
    local region=$1
    
    # Monitor key performance indicators
    az monitor metrics list \
        --resource "$(get_config_value "aks_cluster_prefix")-${region}" \
        --metric "kube_pod_status_ready" "kube_node_status_condition" \
        --output json >> "${LOG_DIR}/performance/${region}_metrics.json"
}

# Alert trigger function
trigger_alert() {
    local severity=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Send to Azure Monitor
    az monitor metrics alert create \
        --name "BesuAlert-${timestamp}" \
        --resource-group "$(get_config_value "resource_group_prefix")" \
        --condition "type=static" \
        --description "${message}" \
        --severity "${severity}"
}

# Resource cleanup
cleanup_resources() {
    # Handle both resource group level and specific resource cleanup
    if [ "$#" -eq 1 ]; then
        # Resource group level cleanup (from deploy.sh)
        local region=$1
        local resource_group="rg-aks-${region}"
        
        log_audit "cleanup_started" "Cleaning up all resources in resource group ${resource_group}"
        echo "Initiating cleanup of resource group ${resource_group}..."
        az group delete --name "${resource_group}" --yes --no-wait || true
        log_audit "cleanup_completed" "Initiated deletion of resource group ${resource_group}"
    elif [ "$#" -eq 4 ]; then
        # Specific resource cleanup (from rollback.sh)
        local resource_group=$1
        local resource_name=$2
        local resource_type=$3
        local namespace=$4
        
        log_audit "cleanup_started" "Cleaning up resource ${resource_name} of type ${resource_type} in ${resource_group}"
        echo "Deleting resource ${resource_name} of type ${resource_type}..."
        az resource delete --resource-group "${resource_group}" --name "${resource_name}" --resource-type "${resource_type}" || true
        log_audit "cleanup_completed" "Deleted resource ${resource_name} in ${resource_group}"
    else
        handle_error 45 "Invalid number of parameters for cleanup_resources: $#"
        echo "Usage: cleanup_resources <region> OR cleanup_resources <resource_group> <resource_name> <resource_type> <namespace>"
    fi
}

# Export functions
export -f handle_error
export -f collect_metrics
export -f check_node_health
export -f log_audit
export -f monitor_performance
export -f trigger_alert
export -f cleanup_resources