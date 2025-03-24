#!/bin/bash

# Source common utilities
source "$(dirname "$0")/config-manager.sh"
source "$(dirname "$0")/log-manager.sh"

# Create resource group if not exists
ensure_resource_group() {
    local name=$1
    local location=$2

    if ! az group exists --name "$name"; then
        log_message "INFO" "Creating resource group $name in $location"
        az group create --name "$name" --location "$location"
        log_audit "resource_group_created" "Created resource group $name in $location"
    else
        log_message "INFO" "Resource group $name already exists"
    fi
}

# Clean up resources
cleanup_resources() {
    # Resource group level cleanup
    if [ "$#" -eq 1 ]; then
        local resource_group=$1
        log_message "INFO" "Cleaning up resource group $resource_group"
        az group delete --name "$resource_group" --yes --no-wait
        log_audit "cleanup_initiated" "Started deletion of resource group $resource_group"
    
    # Individual resource cleanup
    elif [ "$#" -eq 4 ]; then
        local resource_group=$1
        local resource_name=$2
        local resource_type=$3
        local namespace=$4
        
        log_message "INFO" "Cleaning up resource $resource_name of type $resource_type"
        az resource delete \
            --resource-group "$resource_group" \
            --name "$resource_name" \
            --resource-type "$resource_type"
        log_audit "resource_deleted" "Deleted $resource_type $resource_name from $resource_group"
    else
        log_error 60 "Invalid parameters for cleanup_resources"
        return 1
    fi
}

# Get available quotas
get_quotas() {
    local location=$1
    local family=$2
    
    az vm list-usage \
        --location "$location" \
        --query "[?contains(name.value, '$family')].limit" \
        --output tsv
}

# Check resource existence
resource_exists() {
    local resource_group=$1
    local resource_name=$2
    local resource_type=$3

    az resource show \
        --resource-group "$resource_group" \
        --name "$resource_name" \
        --resource-type "$resource_type" \
        --query "id" \
        --output tsv 2>/dev/null
}
