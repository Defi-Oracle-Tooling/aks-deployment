#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Source the deployment utilities (includes configuration loading)
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Use the get_config_value function from the utility
AZURE_REGIONS=$(get_config_value "cloud_providers.azure.regions")
echo "Checking quotas for Azure regions: $AZURE_REGIONS"

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"
REGIONS_FILE=$(get_config_value "cloud_providers.azure.regions")
VM_FAMILIES_FILE=$(get_config_value "cloud_providers.azure.vm_families")
NETWORKS_FILE=$(get_config_value "cloud_providers.azure.networks")
STORAGE_FILE=$(get_config_value "cloud_providers.azure.storage")

TIMESTAMP=$(date "+%Y%m%d_%H%M%S")

# Parse command line arguments
usage() {
    echo "Usage: $0 [--network <mainnet|testnet|devnet>] [--region <region-name>]"
    echo "Default network: mainnet"
    echo "If no region is specified, all enabled regions will be checked"
    exit 1
}

NETWORK="mainnet"
REGION=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --network)
            NETWORK="$2"
            shift
            shift
            ;;
        --region)
            REGION="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate network type
if [[ ! "$NETWORK" =~ ^(mainnet|testnet|devnet)$ ]]; then
    echo "Error: Invalid network type. Must be mainnet, testnet, or devnet."
    exit 1
fi

OUTPUT_FILE="${PROJECT_ROOT}/az_compute_quota_${NETWORK}_${TIMESTAMP}.txt"
CHAIN_ID=$(jq -r ".environments.$NETWORK.chainId" "$VM_FAMILIES_FILE")
NETWORK_NAME=$(jq -r ".environments.$NETWORK.networkName" "$VM_FAMILIES_FILE")

# Check if files exist and are valid JSON
for file in "$REGIONS_FILE" "$VM_FAMILIES_FILE"; do
    if [[ ! -f $file ]] || ! jq empty "$file" 2>/dev/null; then
        echo "Error: $file not found or invalid JSON"
        exit 1
    fi
done

# Create or clear the output file
echo "# Azure Compute Quota Report - $NETWORK_NAME (Chain ID: $CHAIN_ID)" > "$OUTPUT_FILE"
echo "## Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "## Environment Details" >> "$OUTPUT_FILE"
echo "- Network Type: $NETWORK" >> "$OUTPUT_FILE"
echo "- Chain ID: $CHAIN_ID" >> "$OUTPUT_FILE"
echo "- Minimum Nodes: $(jq -r ".metadata.networks.$NETWORK.minNodes" "$VM_FAMILIES_FILE")" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Check if logged into Azure
if ! az account show >/dev/null 2>&1; then
    echo "Error: Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Function to check quotas for a specific region
check_region_quotas() {
    local region_name=$1
    local region_display=$2
    
    echo "## $region_display ($region_name)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "| Node Type | VM Family | Required vCPUs | Current Quota | Used | Available | Status |" >> "$OUTPUT_FILE"
    echo "|-----------|-----------|----------------|---------------|------|-----------|---------|" >> "$OUTPUT_FILE"
    
    # Get quota information for each node type
    jq -r ".environments.$NETWORK.vmFamilies[] | \"\(.name)|\(.useCase)|\(.minVCPUs)\"" "$VM_FAMILIES_FILE" | while IFS='|' read -r vm_family use_case min_vcpus; do
        echo "Checking quotas for $region_name - $vm_family ($use_case)..."
        
        quota_info=$(az vm list-usage --location "$region_name" --query "[?contains(name.value, '$vm_family')]" --output json)
        
        if [[ -n "$quota_info" ]]; then
            current_quota=$(echo $quota_info | jq -r '.[0].limit')
            current_usage=$(echo $quota_info | jq -r '.[0].currentValue')
            available=$((current_quota - current_usage))
            
            # Check if available capacity meets requirements
            if [ "$available" -lt "$min_vcpus" ]; then
                status="⚠️  Insufficient"
            else
                status="✅ Sufficient"
            fi
            
            echo "| $use_case | $vm_family | $min_vcpus | $current_quota | $current_usage | $available | $status |" >> "$OUTPUT_FILE"
        fi
    done
    echo "" >> "$OUTPUT_FILE"
}

# Process regions
if [ -n "$REGION" ]; then
    # Check single region
    region_display=$(jq -r ".regions[] | select(.name == \"$REGION\") | .displayName" "$REGIONS_FILE")
    if [ -n "$region_display" ]; then
        check_region_quotas "$REGION" "$region_display"
    else
        echo "Error: Region $REGION not found in $REGIONS_FILE"
        exit 1
    fi
else
    # Check all enabled regions
    jq -r '.regions[] | select(.enabled == true) | "\(.name)|\(.displayName)"' "$REGIONS_FILE" | while IFS='|' read -r region_name region_display; do
        check_region_quotas "$region_name" "$region_display"
    done
fi

# Add network-specific notes
echo "## Notes" >> "$OUTPUT_FILE"
echo "- Environment: $NETWORK_NAME" >> "$OUTPUT_FILE"
echo "- Minimum node requirements: $(jq -r ".metadata.networks.$NETWORK.minNodes" "$VM_FAMILIES_FILE") nodes" >> "$OUTPUT_FILE"
echo "- Network type: $(jq -r ".metadata.networks.$NETWORK.networkType" "$VM_FAMILIES_FILE")" >> "$OUTPUT_FILE"
echo "- Resource requirements are specific to $NETWORK_NAME deployment" >> "$OUTPUT_FILE"

echo "Quota report generated in $OUTPUT_FILE"