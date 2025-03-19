# Usage

## Steps
1. Ensure `regions.txt` contains the list of regions to deploy to.
2. Run the deployment script:
    ```bash
    ./deploy.sh
    ```
3. Review the log files for deployment status and details:
    - `success_regions.log`: Records regions that were successfully deployed.
    - `failed_regions.log`: Records regions where deployment failed.
    - `deployment.log`: Logs detailed deployment process.

![Usage Steps](images/usage_steps.png)

## Notes
- Ensure you have the necessary permissions to create and manage AKS clusters.
- Review the log files for detailed information on the deployment process and any errors encountered.
