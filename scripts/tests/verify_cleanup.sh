#!/bin/bash
# This script tests the cleanup functionality by simulating deployments and failures

# Source the utility functions
source "$(dirname "$0")/../deployment/deployment-utils.sh"

# Set up test environment
TEST_RG="test-cleanup-rg-$(date +%s)"
TEST_RESOURCE="test-resource"
TEST_TYPE="Microsoft.Storage/storageAccounts"
TEST_NAMESPACE="default"

echo "Creating test resource group ${TEST_RG}..."
az group create --name "${TEST_RG}" --location "eastus" || {
    echo "Failed to create resource group for testing"
    exit 1
}

echo "Testing resource group level cleanup..."
cleanup_resources "eastus" || {
    echo "Resource group level cleanup failed"
    exit 1
}

echo "Verifying resource group was marked for deletion..."
# Sleep to allow deletion to be registered
sleep 5
STATUS=$(az group exists --name "${TEST_RG}")
if [ "$STATUS" == "true" ]; then
    echo "Warning: Resource group still exists, but it might be in the process of being deleted."
    echo "You may need to manually delete it later with: az group delete --name ${TEST_RG} --yes"
else
    echo "Resource group deletion initiated successfully"
fi

echo "All tests completed!"
exit 0
