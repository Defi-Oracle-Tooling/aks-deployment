# Deployment Process

## Steps
1. Clone the repository:
    ```bash
    git clone https://github.com/yourrepo/aks-deployment-1.git
    cd aks-deployment-1
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
