# Deployment Script

## Overview
This script deploys Azure Kubernetes Service (AKS) clusters to multiple regions as specified in `regions.txt`.

## Features
- **State Management**: Records successfully deployed regions in `success_regions.log` and skips them in subsequent runs.
- **Pre-Deployment Check**: Checks if the AKS cluster already exists and is healthy before attempting deployment.
- **Logging**: Logs detailed deployment process in `deployment.log`.
- **Cleanup**: Cleans up partially created resources in case of deployment failures.
- **Notification**: Notifies the team about the deployment status, including both successes and failures.
- **Retry Mechanism**: Retries failed deployments up to 2 times.
- **Rollback**: Rolls back the deployment to the previous state in case of failures.

![Deployment Script](images/deployment_script.png)

## Usage
1. Ensure `regions.txt` contains the list of regions to deploy to.
2. Run the deployment script:
    ```bash
    ./deploy.sh
    ```
3. Review `success_regions.log` for successfully deployed regions, `failed_regions.log` for any failures, and `deployment.log` for detailed deployment process.

## Notes
- Ensure you have the necessary permissions to create and manage AKS clusters.
- Review the log files for deployment status and details.
