# Besu AKS Deployment

This project deploys a **Hyperledger Besu** blockchain network using **Azure Kubernetes Service (AKS)**.

![AKS Deployment](docs/images/aks_deployment.png)

## 🏗️ **Deployment Process**
1. Clone the repo:
    ```bash
    git clone https://github.com/yourrepo/aks-deployment-1.git
    cd aks-deployment-1
    ```
2. Ensure Azure CLI is installed & logged in:
    ```bash
    az login
    az account set --subscription YOUR_SUBSCRIPTION_ID
    ```
3. Deploy AKS clusters across all regions:
    ```bash
    chmod +x deploy.sh
    ./deploy.sh
    ```

## 📌 **How This Works**
- **Reads `regions.txt`** for all supported Azure regions.
- **Fetches available vCPU quotas** dynamically.
- **Chooses the best VM size (`D16s_v4`, `D4s_v4`, `D2s_v4`)**.
- **Automatically scales nodes** based on quotas.
- **Retries failed deployments** up to 2 times.
- **Logs errors in `failed_regions.log`**.
- **Logs successful deployments in `success_regions.log`**.
- **Logs detailed deployment process in `deployment.log`**.
- **Triggers alerts via Azure Monitor if deployments fail**.
- **Cleans up partially created resources in case of deployment failures**.

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
