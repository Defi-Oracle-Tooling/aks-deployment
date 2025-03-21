#!/bin/bash

# Load region list
regions=$(cat regions.txt)

# Log files for deployment states
SUCCESS_FILE="success_regions.log"
FAILED_FILE="failed_regions.log"
LOG_FILE="deployment.log"
ROLLBACK_FILE="rollback.log"
echo "" > $FAILED_FILE

RESOURCE_GROUP_PREFIX="Besu-RG"
AKS_CLUSTER_PREFIX="besu-aks"
QUOTAS_FILE="quotas_20250319-0530.md"

# Check if regions.txt is not empty
if [ ! -s regions.txt ]; then
    echo "Error: regions.txt is empty or not found." | tee -a $LOG_FILE
    exit 1
fi

# Check if RESOURCE_GROUP_PREFIX and AKS_CLUSTER_PREFIX are set
if [ -z "$RESOURCE_GROUP_PREFIX" ] || [ -z "$AKS_CLUSTER_PREFIX" ]; then
    echo "Error: RESOURCE_GROUP_PREFIX or AKS_CLUSTER_PREFIX is not set." | tee -a $LOG_FILE
    exit 1
fi

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

# Function to determine optimal instance size
get_instance_size() {
    local vCPU_LIMIT=$1
    if [[ $vCPU_LIMIT -ge 128 ]]; then
        echo "Standard_D16s_v4 6"
    elif [[ $vCPU_LIMIT -ge 32 ]]; then
        echo "Standard_D8s_v4 7"
    elif [[ $vCPU_LIMIT -ge 24 ]]; then
        echo "Standard_D4s_v4 5"
    elif [[ $vCPU_LIMIT -ge 10 ]]; then
        echo "Standard_D2s_v4 4"
    else
        echo ""
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
    if is_region_deployed "$region"; then
        echo "Region $region already deployed successfully. Skipping..." | tee -a $LOG_FILE
        return
    fi

    echo "🚀 Deploying AKS in $region..." | tee -a $LOG_FILE

    vCPU_LIMIT=$(fetch_vcpu_quota $region)
    instance_info=$(get_instance_size $vCPU_LIMIT)
    if [[ -z $instance_info ]]; then
        echo "⚠️ Skipping $region: Not enough vCPUs available ($vCPU_LIMIT)" | tee -a $FAILED_FILE $LOG_FILE
        return
    fi

    NODE_TYPE=$(echo $instance_info | cut -d' ' -f1)
    NODE_COUNT=$(echo $instance_info | cut -d' ' -f2)

    echo "📌 Region: $region | vCPU: $vCPU_LIMIT | VM Size: $NODE_TYPE | Nodes: $NODE_COUNT" | tee -a $LOG_FILE

    if is_cluster_healthy "$RESOURCE_GROUP_PREFIX-$region" "$AKS_CLUSTER_PREFIX-$region"; then
        echo "AKS cluster in region $region is already healthy. Skipping deployment..." | tee -a $LOG_FILE
        echo "$region" >> "$SUCCESS_FILE"
        return
    fi

    if ! create_resource_group $region; then
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
}

# Function to clean up partially created resources
cleanup_resources() {
    local region=$1
    az group delete --name "$RESOURCE_GROUP_PREFIX-$region" --yes --no-wait
}

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
export -f create_resource_group
export -f deploy_aks
export -f deploy_validator_nodes
export -f deploy_to_region
export -f cleanup_resources
export -f rollback_deployment

parallel deploy_to_region ::: $(cat regions.txt)

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
