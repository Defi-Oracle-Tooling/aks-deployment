#!/bin/bash

# Define node allocation per region
declare -A NODE_ALLOCATION
NODE_ALLOCATION["australiaeast"]="5,7,0"
NODE_ALLOCATION["canadacentral"]="5,7,0"
NODE_ALLOCATION["francecentral"]="5,7,0"
NODE_ALLOCATION["israelcentral"]="5,7,0"
NODE_ALLOCATION["switzerlandnorth"]="5,7,0"
NODE_ALLOCATION["australiacentral"]="0,8,0"
NODE_ALLOCATION["australiasoutheast"]="0,8,0"
NODE_ALLOCATION["southindia"]="0,8,0"
NODE_ALLOCATION["ukwest"]="0,8,0"
NODE_ALLOCATION["eastasia"]="0,6,0"
NODE_ALLOCATION["northeurope"]="0,6,0"
NODE_ALLOCATION["southeastasia"]="0,6,0"
NODE_ALLOCATION["westeurope"]="0,6,0"
NODE_ALLOCATION["brazilsouth"]="0,0,5"
NODE_ALLOCATION["centralindia"]="0,0,5"
NODE_ALLOCATION["germanywestcentral"]="0,0,5"
NODE_ALLOCATION["indonesiacentral"]="0,0,5"
NODE_ALLOCATION["italynorth"]="0,0,5"
NODE_ALLOCATION["japaneast"]="0,0,5"
NODE_ALLOCATION["japanwest"]="0,0,5"
NODE_ALLOCATION["koreacentral"]="0,0,5"
NODE_ALLOCATION["mexicocentral"]="0,0,5"
NODE_ALLOCATION["newzealandnorth"]="0,0,5"
NODE_ALLOCATION["norwayeast"]="0,0,5"
NODE_ALLOCATION["polandcentral"]="0,0,5"
NODE_ALLOCATION["southafricanorth"]="0,0,5"
NODE_ALLOCATION["spaincentral"]="0,0,5"
NODE_ALLOCATION["swedencentral"]="0,0,5"
NODE_ALLOCATION["uaenorth"]="0,0,5"
NODE_ALLOCATION["uksouth"]="0,0,5"

# Regions to deploy AKS
regions=("${!NODE_ALLOCATION[@]}")
RESOURCE_GROUP_PREFIX="Besu-RG"
AKS_CLUSTER_PREFIX="besu-aks"
LOG_FILE="failed_regions.log"
RETRY_LIMIT=2

# Clear previous failure log
echo "" > $LOG_FILE

for region in "${regions[@]}"; do
    echo "Deploying AKS in $region..."

    IFS=',' read -r d16_count d4_count d2_count <<< "${NODE_ALLOCATION[$region]}"

    # Create resource group
    az group create --name "$RESOURCE_GROUP_PREFIX-$region" --location $region || {
        echo "❌ Failed to create resource group in $region" >> $LOG_FILE
        continue
    }

    # Deploy AKS with node pools
    for attempt in $(seq 1 $RETRY_LIMIT); do
        az aks create --resource-group "$RESOURCE_GROUP_PREFIX-$region" --name "$AKS_CLUSTER_PREFIX-$region" \
            --nodepool-name "validator16" --node-count $d16_count --node-vm-size "Standard_D16s_v4" \
            --enable-managed-identity --generate-ssh-keys && break || {
                echo "❌ Attempt $attempt: Failed AKS deployment in $region" >> $LOG_FILE
                sleep 10
            }
    done

    az aks nodepool add --resource-group "$RESOURCE_GROUP_PREFIX-$region" --cluster-name "$AKS_CLUSTER_PREFIX-$region" \
        --name "validator4" --node-count $d4_count --node-vm-size "Standard_D4s_v4" || {
            echo "❌ Failed to add D4s_v4 nodes in $region" >> $LOG_FILE
        }

    az aks nodepool add --resource-group "$RESOURCE_GROUP_PREFIX-$region" --cluster-name "$AKS_CLUSTER_PREFIX-$region" \
        --name "validator2" --node-count $d2_count --node-vm-size "Standard_D2s_v4" || {
            echo "❌ Failed to add D2s_v4 nodes in $region" >> $LOG_FILE
        }

    echo "✅ AKS Deployment in $region completed!"
done

# Alert if failures occurred
if [[ -s $LOG_FILE ]]; then
    echo "⚠️ Some regions failed to deploy. See $LOG_FILE"
    az monitor metrics alert create --name "AKSDeploymentFailure" --resource-group "$RESOURCE_GROUP_PREFIX" \
        --scopes "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_PREFIX" \
        --description "Alert for AKS deployment failures" --condition "count failed_regions.log > 0" \
        --action-group "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_PREFIX/providers/microsoft.insights/actionGroups/AKSFailureAlerts"
fi
