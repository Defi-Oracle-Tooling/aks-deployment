#!/bin/bash

# Load Azure regions from file
regions=$(cat regions.txt)

# Azure resource group and AKS cluster naming conventions
RESOURCE_GROUP_PREFIX="Besu-RG"
AKS_CLUSTER_PREFIX="besu-aks"

# Loop through each region and deploy AKS
for region in $regions; do
    echo "Deploying AKS in $region..."

    # Create resource group and check if it's created successfully
    if az group create --name "$RESOURCE_GROUP_PREFIX-$region" --location $region; then
        echo "Resource group created in $region."
    else
        echo "Skipping $region - Resource group creation failed."
        continue
    fi

    # Deploy AKS using ARM template
    az deployment group create \
        --resource-group "$RESOURCE_GROUP_PREFIX-$region" \
        --template-file aks-deploy.json \
        --parameters location="$region" aksName="$AKS_CLUSTER_PREFIX-$region"

    echo "AKS Deployment in $region completed!"
done
