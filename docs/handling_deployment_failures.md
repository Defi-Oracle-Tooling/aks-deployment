# Handling Deployment Failures

## Overview
The deployment script includes mechanisms to handle deployment failures, log errors, and clean up partially created resources.

## Steps
1. **Log Errors**: The script logs errors in `failed_regions.log`.
2. **Trigger Alerts**: The script triggers alerts via Azure Monitor if deployments fail.
3. **Cleanup Resources**: The script cleans up partially created resources in case of deployment failures.
4. **Retry Mechanism**: The script retries failed deployments up to 2 times.
5. **Rollback**: The script rolls back the deployment to the previous state in case of failures.
6. **Notification**: The script notifies the team about the deployment status, including both successes and failures.

![Handling Failures](images/handling_failures.png)

## Notes
- Review the `failed_regions.log` file for detailed error messages and specific error codes from the Azure CLI.
- Ensure you have the necessary permissions to delete and manage resources in your Azure subscription.
