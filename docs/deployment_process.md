# Deployment Process

## Overview
Each network type (Mainnet, Testnet, Devnet) has specific resource requirements and configurations for optimal performance and security.

## Network Types

### Mainnet (Chain ID: 138)
- Production-grade deployment
- High resource requirements
- Premium storage and networking
- Minimum 7 nodes for consensus
- Uses premium VM families (DSv4, ESv4, ESv5)

### Testnet (Chain ID: 2138)
- Testing environment deployment
- Moderate resource requirements
- Standard storage and networking
- Minimum 4 nodes for consensus
- Uses standard VM families (Ev4, Ev5, FSv2)

### Devnet (Chain ID: 1337)
- Development environment deployment
- Minimal resource requirements
- Standard storage and networking
- Minimum 1 node required
- Uses cost-effective VM families (BSv2, FSv2)

## Process Flow

1. **Pre-deployment Checks**
   - Verify regions.txt exists and is not empty
   - Validate environment variables
   - Check Azure CLI authentication

2. **Resource Group Management**
   - Check if resource group exists for each region
   - Create resource group if it doesn't exist
   - Validate resource group state before proceeding

3. **Quota and Sizing**
   - Ensure sufficient quota for required resources
   - Validate resource sizing parameters

4. **Deployment**
   - Check for existing healthy AKS clusters
   - Deploy new clusters where needed
   - Deploy validator nodes
   - Record successful deployments

5. **Error Handling**
   - Log failed deployments
   - Attempt automatic retry for failed regions
   - Clean up partial resources if needed using the unified cleanup mechanism
   - Trigger notifications for failures

6. **Monitoring**
   - Monitor deployment status
   - Collect and analyze metrics

## Retry Mechanism
The deployment includes a two-level retry system:
1. Individual deployment attempts are retried up to 2 times
2. Failed regions are automatically retried after initial deployment completion

## Logging
The process generates several log files:
- `deployment.log`: Detailed deployment process
- `success_regions.log`: Successfully deployed regions
- `failed_regions.log`: Failed deployment regions
- `rollback.log`: Resource cleanup operations
- `audit.log`: Detailed audit trail including all cleanup operations

## Cleanup Process
The deployment includes a unified cleanup mechanism:
1. Centralized in `deployment-utils.sh` for consistent implementation
2. Used by both deployment and rollback scripts
3. Supports two modes:
   - Resource group level cleanup: `cleanup_resources <region>`
   - Specific resource cleanup: `cleanup_resources <resource_group> <resource_name> <resource_type> <namespace>`
4. All cleanup operations are logged in the audit log

## Deployment Steps

1. Select Network Type:
   ```bash
   # Set the network type (mainnet, testnet, or devnet)
   export NETWORK_TYPE=mainnet
   ```

2. Check Azure Quotas:
   ```bash
   ./scripts/check_quotas.sh $NETWORK_TYPE
   ```

3. Review Quota Report:
   - Check for sufficient vCPU availability
   - Verify storage capacity
   - Confirm network resources

4. Deploy Network:
   ```bash
   ./scripts/deploy.sh --network $NETWORK_TYPE
   ```

5. Monitor Deployment:
   - Track progress in deployment.log
   - Check for region-specific issues
   - Monitor node health and consensus

## Resource Requirements by Network

### Mainnet
- Validators:
  - CPU: 24 vCPUs
  - Memory: 32GB
  - Storage: 512GB Premium SSD
- Boot Nodes:
  - CPU: 16 vCPUs
  - Memory: 64GB
  - Storage: 1TB Premium SSD
- RPC Nodes:
  - CPU: 16 vCPUs
  - Memory: 64GB
  - Storage: 2TB Premium SSD

### Testnet
- Validators:
  - CPU: 8 vCPUs
  - Memory: 16GB
  - Storage: 256GB Standard SSD
- Boot Nodes:
  - CPU: 8 vCPUs
  - Memory: 32GB
  - Storage: 512GB Standard SSD
- RPC Nodes:
  - CPU: 8 vCPUs
  - Memory: 32GB
  - Storage: 512GB Standard SSD

### Devnet
- All Nodes:
  - CPU: 4 vCPUs
  - Memory: 8GB
  - Storage: 128GB Standard SSD
- Validators (Optional):
  - CPU: 4 vCPUs
  - Memory: 16GB
  - Storage: 256GB Standard SSD

## Steps
1. Clone the repository:
    ```bash
    git clone https://github.com/yourrepo/ABCDEfGHIJKL.git
    cd ABCDEfGHIJKL
    ```
2. Ensure Azure CLI is installed and logged in:
    ```bash
    az login
    az account set --subscription YOUR_SUBSCRIPTION_ID
    ```
3. Deploy AKS clusters across all regions:
    ```bash
    chmod +x deploy.sh
    ./deploy.sh
    ```

![Deployment Steps](images/deployment_steps.png)

## Notes
- Ensure you have the necessary permissions to create and manage AKS clusters.
- Review the log files (`success_regions.log`, `failed_regions.log`, `deployment.log`) for deployment status and details.
