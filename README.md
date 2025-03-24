# BESU_AKS_DEPLOYMENT

THIS_PROJECT_DEPLOYS_A_**HYPERLEDGER_BESU**_BLOCKCHAIN_NETWORK_USING_**AZURE_KUBERNETES_SERVICE_(AKS)**.

![AKS_DEPLOYMENT](docs/images/aks_deployment.png)

## 🏗️_**DEPLOYMENT_PROCESS**
1._CLONE_THE_REPO:
    ```bash
    git_clone_https://github.com/yourrepo/aks-deployment-1.git
    cd_aks-deployment-1
    ```
2._ENSURE_AZURE_CLI_IS_INSTALLED_&_LOGGED_IN:
    ```bash
    az_login
    az_account_set_--subscription_YOUR_SUBSCRIPTION_ID
    ```
3._DEPLOY_AKS_CLUSTERS_ACROSS_ALL_REGIONS:
    ```bash
    chmod_+x_deploy.sh
    ./deploy.sh
    ```

## 📌_**HOW_THIS_WORKS**
-_**READS_`regions.txt`**_FOR_ALL_SUPPORTED_AZURE_REGIONS.
-_**FETCHES_AVAILABLE_VCPU_QUOTAS**_DYNAMICALLY.
-_**CHOOSES_THE_BEST_VM_SIZE_(`D16s_v4`,_`D4s_v4`,_`D2s_v4`)**.
-_**AUTOMATICALLY_SCALES_NODES**_BASED_ON_QUOTAS.
-_**RETRIES_FAILED_DEPLOYMENTS**_UP_TO_2_TIMES.
-_**LOGS_ERRORS_IN_`failed_regions.log`**.
-_**LOGS_SUCCESSFUL_DEPLOYMENTS_IN_`success_regions.log`**.
-_**LOGS_DETAILED_DEPLOYMENT_PROCESS_IN_`deployment.log`**.
-_**TRIGGERS_ALERTS_VIA_AZURE_MONITOR_IF_DEPLOYMENTS_FAIL**.

![Deployment Workflow](docs/images/deployment_workflow.png)

## 📚 **Documentation**
- [Deployment Process](docs/deployment_process.md)
- [How This Works](docs/how_this_works.md)
- [Handling Deployment Failures](docs/handling_deployment_failures.md)
- [Quota Overview](docs/quota_overview.md)
- [Deployment Script](docs/deployment_script.md)
- [Usage](docs/usage.md)
- [Files](docs/files.md)
- [Prerequisites](docs/prerequisites.md)
- [Notes](docs/notes.md)

## ⚠️ **Handling Deployment Failures**
- Errors are logged in `failed_regions.log`.
- Azure Monitor alerts are triggered for failures.
- Partially created resources are cleaned up.

## 📊 **Quota Overview**
| **Region** | **Max vCPUs**    | **Optimal VM** | **Node Count** |
|------------|------------------|----------------|----------------|
| 108        | Standard_D16s_v4 | 6              |
| 32         | Standard_D4s_v4  | 7              |
| 24         | Standard_D4s_v4  | 5              |
| 10         | Standard_D2s_v4  | 4              |

# AKS Deployment Script

## Overview
This script deploys Azure Kubernetes Service (AKS) clusters to multiple regions as specified in `regions.txt`.

## New Features
- **State Management:** The script now records successfully deployed regions in `success_regions.log` and skips them in subsequent runs.
- **Pre-Deployment Check:** The script checks if the AKS cluster already exists and is healthy before attempting deployment.
- **Logging:** The script logs detailed deployment process in `deployment.log`.
- **Cleanup:** The script cleans up partially created resources in case of deployment failures.
- **Notification:** The script notifies the team about the deployment status, including both successes and failures.
- **Cleanup:** The script provides a unified cleanup mechanism to remove resources in case of deployment failures. The cleanup functionality:
  - Is centralized in the `scripts/deployment/deployment-utils.sh` file
  - Can remove entire resource groups or individual resources
  - Logs all cleanup operations to the audit log
  - Is used by both the deployment and rollback scripts
  - Handles both resource group level and specific resource cleanup
  - Logs all cleanup operations to the audit log
  - Is centralized in the deployment-utils.sh file for consistent behavior
  - Can be triggered automatically on failure or manually through dedicated commands

## Usage
1. Ensure `regions.txt` contains the list of regions to deploy to.
2. Run the deployment script:
    ```bash
    ./deploy.sh
    ```
3. Review `success_regions.log` for successfully deployed regions, `failed_regions.log` for any failures, and `deployment.log` for detailed deployment process.

## Files
- `regions.txt`: List of regions to deploy to.
- `success_regions.log`: Records regions that were successfully deployed.
- `failed_regions.log`: Records regions where deployment failed.
- `deployment.log`: Logs detailed deployment process.

## Prerequisites
- Azure CLI must be installed and authenticated.
- Ensure the necessary permissions to create and manage AKS clusters.

## Notes
- The script will skip regions listed in `success_regions.log`.
- If a region's AKS cluster is already healthy, it will be skipped and recorded in `success_regions.log`.
- The script cleans up partially created resources in case of deployment failures.
- The script notifies the team about the deployment status, including both successes and failures.

