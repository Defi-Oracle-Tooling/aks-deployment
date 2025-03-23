#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Source the deployment utilities (includes configuration loading)
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Use the get_config_value function from the utility
AZURE_REGIONS=$(get_config_value "cloud_providers.azure.regions")
echo "Deploying to Azure regions: $AZURE_REGIONS"

# Create config directory
mkdir -p config

# Move existing configuration files
mv infrastructure/configs/regions.json config/
mv infrastructure/configs/vm_families.json config/

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"

# Azure configuration paths
AZURE_REGIONS_FILE=$(jq -r '.azure.regions' "$CONFIG_PATHS_FILE")
AZURE_VM_FAMILIES_FILE=$(jq -r '.azure.vm_families' "$CONFIG_PATHS_FILE")
AZURE_NETWORKS_FILE=$(jq -r '.azure.networks' "$CONFIG_PATHS_FILE")
AZURE_STORAGE_FILE=$(jq -r '.azure.storage' "$CONFIG_PATHS_FILE")

# AWS configuration paths
AWS_REGIONS_FILE=$(jq -r '.aws.regions' "$CONFIG_PATHS_FILE")
AWS_INSTANCE_TYPES_FILE=$(jq -r '.aws.instance_types' "$CONFIG_PATHS_FILE")
AWS_NETWORKS_FILE=$(jq -r '.aws.networks' "$CONFIG_PATHS_FILE")
AWS_STORAGE_FILE=$(jq -r '.aws.storage' "$CONFIG_PATHS_FILE")

# GCP configuration paths
GCP_REGIONS_FILE=$(jq -r '.gcp.regions' "$CONFIG_PATHS_FILE")
GCP_MACHINE_TYPES_FILE=$(jq -r '.gcp.machine_types' "$CONFIG_PATHS_FILE")
GCP_NETWORKS_FILE=$(jq -r '.gcp.networks' "$CONFIG_PATHS_FILE")
GCP_STORAGE_FILE=$(jq -r '.gcp.storage' "$CONFIG_PATHS_FILE")

# Common configuration paths
LOGGING_FILE=$(jq -r '.common.logging' "$CONFIG_PATHS_FILE")
MONITORING_FILE=$(jq -r '.common.monitoring' "$CONFIG_PATHS_FILE")
SECURITY_FILE=$(jq -r '.common.security' "$CONFIG_PATHS_FILE")

# Environment configuration paths
PRODUCTION_ENV_FILE=$(jq -r '.environments.production' "$CONFIG_PATHS_FILE")
STAGING_ENV_FILE=$(jq -r '.environments.staging' "$CONFIG_PATHS_FILE")
DEVELOPMENT_ENV_FILE=$(jq -r '.environments.development' "$CONFIG_PATHS_FILE")

# GitHub configuration paths
GITHUB_ACTIONS_FILE=$(jq -r '.github.actions' "$CONFIG_PATHS_FILE")
GITHUB_SECRETS_FILE=$(jq -r '.github.secrets' "$CONFIG_PATHS_FILE")

# Log files
SUCCESS_FILE="success_regions.log"
FAILED_FILE="failed_regions.log"
LOG_FILE="deployment.log"
ROLLBACK_FILE="rollback.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --network)
            NETWORK="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default to mainnet if not specified
NETWORK=${NETWORK:-mainnet}
CHAIN_ID=$(jq -r ".environments.$NETWORK.chainId" "$AZURE_VM_FAMILIES_FILE")
NETWORK_NAME=$(jq -r ".environments.$NETWORK.networkName" "$AZURE_VM_FAMILIES_FILE")

echo "" > $FAILED_FILE

# Load network-specific configurations
for file in "$AZURE_REGIONS_FILE" "$AZURE_VM_FAMILIES_FILE"; do
    if [[ ! -f $file ]] || ! jq empty "$file" 2>/dev/null; then
        echo "Error: $file not found or invalid JSON" | tee -a $LOG_FILE
        exit 1
    fi
    echo "Loaded configuration from $file" | tee -a $LOG_FILE
done

# Log deployment start
echo "Starting deployment for $NETWORK_NAME (Chain ID: $CHAIN_ID)" | tee -a $LOG_FILE
echo "Minimum nodes required: $(jq -r ".metadata.networks.$NETWORK.minNodes" "$AZURE_VM_FAMILIES_FILE")" | tee -a $LOG_FILE

# Function to check if a region is already successfully deployed
is_region_deployed() {
    local region=$1
    grep -q "^$region$" "$SUCCESS_FILE"
}

# Function to check if the AKS cluster exists and is healthy
is_cluster_healthy() {
    local resource_group=$1
    local cluster_name=$2
    az aks show --resource-group "$resource_group" --name "$cluster_name" --query "provisioningState" -o tsv | grep -q "Succeeded"
}

# Function to fetch vCPU quota dynamically
fetch_vcpu_quota() {
    local region=$1
    az vm list-usage --location $region --query "[?name.value=='standardDSv4Family'].limit" --output tsv
}

# Function to determine optimal instance size based on network type
get_instance_size() {
    local vCPU_LIMIT=$1
    local NETWORK=$2
    local NODE_TYPE=$3

    case $NETWORK in
        "mainnet")
            case $NODE_TYPE in
                "validator")
                    if [[ $vCPU_LIMIT -ge 24 ]]; then
                        echo "Standard_DSv4Family 7"
                    fi
                    ;;
                "bootnode")
                    if [[ $vCPU_LIMIT -ge 16 ]]; then
                        echo "Standard_ESv4Family 3"
                    fi
                    ;;
                "rpc")
                    if [[ $vCPU_LIMIT -ge 16 ]]; then
                        echo "Standard_ESv5Family 3"
                    fi
                    ;;
            esac
            ;;
        "testnet")
            case $NODE_TYPE in
                "validator")
                    if [[ $vCPU_LIMIT -ge 8 ]]; then
                        echo "Standard_Ev4Family 4"
                    fi
                    ;;
                "bootnode"|"rpc")
                    if [[ $vCPU_LIMIT -ge 8 ]]; then
                        echo "Standard_FSv2Family 2"
                    fi
                    ;;
            esac
            ;;
        "devnet")
            if [[ $vCPU_LIMIT -ge 4 ]]; then
                echo "Standard_BSv2Family 1"
            fi
            ;;
    esac
    echo ""
}

# Function to determine optimal instance size based on network type (generic and referenced implementation)
get_instance_size_generic() {
    local vCPU_LIMIT=$1
    local NETWORK=$2
    local NODE_TYPE=$3
    local CONFIG_FILE=$4

    local instance_info=$(jq -r ".${NETWORK}.${NODE_TYPE}[] | select(.vCPU <= ${vCPU_LIMIT}) | .family, .nodes" ${CONFIG_FILE} | tail -n 2)

    if [[ -n $instance_info ]]; then
        echo "$instance_info"
    else
        echo ""
    fi
}

# Generic method to get instance size
get_generic_instance_size() {
    local vCPU_LIMIT=$1
    local NETWORK=$2
    local NODE_TYPE=$3
    local CONFIG_FILE=$4

    local instance_info=$(jq -r ".environments.$NETWORK.nodeTypes.$NODE_TYPE | select(.vCPULimit <= $vCPU_LIMIT) | .vmFamily, .nodeCount" "$CONFIG_FILE")

    if [[ -z $instance_info ]]; then
        echo ""
    else
        echo "$instance_info"
    fi
}

# Function to check if a resource group exists
check_resource_group_exists() {
    local region=$1
    az group exists --name "${RESOURCE_GROUP_PREFIX}-${region}"
}

# Function to create resource group if it does not exist
create_resource_group_if_not_exists() {
    local region=$1
    if ! check_resource_group_exists $region; then
        az group create --name "${RESOURCE_GROUP_PREFIX}-${region}" --location $region
    else
        echo "Resource group ${RESOURCE_GROUP_PREFIX}-${region} already exists."
    fi
}

# Function to create resource group
create_resource_group() {
    local region=$1
    az group create --name "${RESOURCE_GROUP_PREFIX}-${region}" --location $region
}

# Function to deploy AKS
deploy_aks() {
    local region=$1
    local NODE_TYPE=$2
    local NODE_COUNT=$3
    for attempt in {1..2}; do
        az deployment group create --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
            --template-file aks-deploy.json \
            --parameters aks-deploy.parameters.json \
            --parameters location="$region" bootNodeCount="$NODE_COUNT" adminNodeCount="$NODE_COUNT" assignedNodeCount="$NODE_COUNT" publicNodeCount="$NODE_COUNT" regulatedNodeCount="$NODE_COUNT" && return 0 || {
                echo "❌ Attempt $attempt: Failed AKS deployment in $region" >> $FAILED_FILE
                sleep 10
            }
    done
    return 1
}

# Function to deploy validator nodes
deploy_validator_nodes() {
    local region=$1
    local NODE_COUNT=$2
    for attempt in {1..2}; do
        az deployment group create --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
            --template-file aks-deploy-validator.json \
            --parameters aks-deploy.parameters.json \
            --parameters location="$region" validatorNodeCount="$NODE_COUNT" && return 0 || {
                echo "❌ Attempt $attempt: Failed validator nodes deployment in $region" >> $FAILED_FILE
                sleep 10
            }
    done
    return 1
}

# Function to deploy to a region
deploy_to_region() {
    local region=$1
    local NETWORK=$2

    if is_region_deployed "$region"; then
        echo "Region $region already deployed successfully. Skipping..." | tee -a $LOG_FILE
        return
    fi

    echo "🚀 Deploying AKS in $region for $NETWORK..." | tee -a $LOG_FILE

    # Get minimum nodes required for this network
    MIN_NODES=$(jq -r ".metadata.networks.$NETWORK.minNodes" "$AZURE_VM_FAMILIES_FILE")

    # Check quotas for each node type
    for NODE_TYPE in "validator" "bootnode" "rpc"; do
        vCPU_LIMIT=$(fetch_vcpu_quota $region)
        instance_info=$(get_generic_instance_size $vCPU_LIMIT "$NETWORK" "$NODE_TYPE" "$AZURE_VM_FAMILIES_FILE")

        if [[ -z $instance_info ]]; then
            echo "⚠️ Skipping $region: Not enough vCPUs for $NODE_TYPE nodes ($vCPU_LIMIT needed)" | tee -a $FAILED_FILE $LOG_FILE
            return 1
        fi

        VM_SIZE=$(echo $instance_info | cut -d' ' -f1)
        NODE_COUNT=$(echo $instance_info | cut -d' ' -f2)

        echo "📌 Region: $region | Node Type: $NODE_TYPE | VM Size: $VM_SIZE | Nodes: $NODE_COUNT" | tee -a $LOG_FILE

        # Rest of the deployment logic
        if is_cluster_healthy "$RESOURCE_GROUP_PREFIX-$region" "$AKS_CLUSTER_PREFIX-$region"; then
            echo "AKS cluster in region $region is already healthy. Skipping deployment..." | tee -a $LOG_FILE
            echo "$region" >> "$SUCCESS_FILE"
            return
        fi

        if ! create_resource_group_if_not_exists $region; then
            echo "❌ Failed to create resource group in $region" | tee -a $FAILED_FILE $LOG_FILE
            return
        fi

        if deploy_aks $region $NODE_TYPE $NODE_COUNT && deploy_validator_nodes $region $NODE_COUNT; then
            echo "$region" >> "$SUCCESS_FILE"
            echo "✅ Deployment in $region completed!" | tee -a $LOG_FILE
        else
            echo "$region" >> "$FAILED_FILE"
            echo "❌ Deployment in $region failed!" | tee -a $LOG_FILE
        fi
    done
}

# Function to clean up partially created resources
# This is now a wrapper around the unified function in deployment-utils.sh
if ! command -v cleanup_resources &> /dev/null; then
    source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"
fi

# Function to rollback deployment
rollback_deployment() {
    local region=$1
    echo "Rolling back deployment in $region..." | tee -a $ROLLBACK_FILE
    cleanup_resources $region
    echo "Rollback completed for $region" | tee -a $ROLLBACK_FILE
}

# Parallel deployment to regions
export -f is_region_deployed
export -f is_cluster_healthy
export -f fetch_vcpu_quota
export -f get_instance_size
export -f get_instance_size_generic
export -f get_generic_instance_size
export -f create_resource_group
export -f deploy_aks
export -f deploy_validator_nodes
export -f deploy_to_region
export -f cleanup_resources
export -f rollback_deployment

jq -r ".regions[] | select(.enabled == true) | .name" "$AZURE_REGIONS_FILE" | while read -r region; do
    echo "Deploying to $region for $NETWORK_NAME..." | tee -a $LOG_FILE
    
    # Get VM family configuration for the current network
    vm_family_config=$(jq -r ".environments.$NETWORK.vmFamilies[] | select(.recommended == true) | .name" "$AZURE_VM_FAMILIES_FILE" | head -n 1)
    
    if deploy_to_region "$region" "$vm_family_config" "$NETWORK"; then
        echo "$region" >> "$SUCCESS_FILE"
        echo "✅ Deployment in $region completed!" | tee -a $LOG_FILE
    else
        echo "$region" >> "$FAILED_FILE"
        echo "❌ Deployment in $region failed!" | tee -a $LOG_FILE
    fi
done

# Retry deployment for failed regions
if [[ -s $FAILED_FILE ]]; then
    echo "⚠️ Retrying deployment for failed regions..." | tee -a $LOG_FILE
    while IFS= read -r region; do
        deploy_to_region $region
    done < $FAILED_FILE
fi

# Notify on failures
if [[ -s $FAILED_FILE ]]; then
    echo "⚠️ Some regions failed to deploy. Check $FAILED_FILE." | tee -a $LOG_FILE
    az monitor metrics alert create --name "AKSDeploymentFailure" --resource-group "$RESOURCE_GROUP_PREFIX" \
        --scopes "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_PREFIX" \
        --description "Alert for AKS deployment failures" --condition "count failed_regions.log > 0" \
        --action "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_PREFIX/providers/microsoft.insights/actionGroups/AKSFailureAlerts"

    # Cleanup partially created resources
    while IFS= read -r region; do
        cleanup_resources $region
        rollback_deployment $region
    done < $FAILED_FILE
fi

# Notify on success
if [[ -s $SUCCESS_FILE ]]; then
    echo "✅ All regions deployed successfully. Check $SUCCESS_FILE." | tee -a $LOG_FILE
fi
