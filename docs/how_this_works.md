# How This Works

## Overview
The deployment script reads the `regions.txt` file for all supported Azure regions, fetches available vCPU quotas dynamically, chooses the best VM size, and automatically scales nodes based on quotas.

## Steps
1. **Read Regions**: The script reads the `regions.txt` file to get the list of regions to deploy to.
2. **Fetch vCPU Quotas**: The script fetches the available vCPU quotas for each region dynamically using the Azure CLI.
3. **Choose VM Size**: Based on the available vCPU quotas, the script chooses the best VM size (`D16s_v4`, `D4s_v4`, `D2s_v4`).
4. **Scale Nodes**: The script automatically scales the number of nodes based on the chosen VM size and available quotas.
5. **Retry Mechanism**: The script retries failed deployments up to 2 times.
6. **Logging**: The script logs errors in `failed_regions.log`, successful deployments in `success_regions.log`, and detailed deployment process in `deployment.log`.
7. **Cleanup**: The script cleans up partially created resources in case of deployment failures.
8. **Notification**: The script triggers alerts via Azure Monitor if deployments fail and notifies the team about the deployment status.

![How This Works](images/how_this_works.png)
