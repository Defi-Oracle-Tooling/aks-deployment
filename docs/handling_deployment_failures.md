# Handling Deployment Failures

## Overview
The deployment script includes mechanisms to handle deployment failures, log errors, and clean up partially created resources.

## Steps
1. **Log Errors**: The script logs errors in `failed_regions.log`.
2. **Trigger Alerts**: The script triggers alerts via Azure Monitor if deployments fail.
3. **Unified Cleanup Resources**: The script provides a unified cleanup mechanism to remove partially created resources in case of deployment failures.
   - Can clean up entire resource groups or individual resources as needed
   - Maintains detailed audit logs of all cleanup operations
4. **Retry Mechanism**: The script retries failed deployments up to 2 times.
5. **Rollback**: The script rolls back the deployment to the previous state in case of failures.
6. **Notification**: The script notifies the team about the deployment status, including both successes and failures.

![Handling Failures](images/handling_failures.png)

## Cleanup Implementation
- The unified cleanup functionality is implemented in `scripts/deployment/deployment-utils.sh`
- All scripts (deploy.sh, rollback.sh, etc.) use this centralized implementation
- It can handle both resource group level cleanup and specific resource cleanup
- All cleanup operations are logged to the audit log for traceability
- The cleanup function can be invoked with:
  - `cleanup_resources <region>` for resource group level cleanup
  - `cleanup_resources <resource_group> <resource_name> <resource_type> <namespace>` for specific resource cleanup

## Notes
- Review the `failed_regions.log` file for detailed error messages and specific error codes from the Azure CLI.
- Check the audit logs for details about cleanup operations
- Ensure you have the necessary permissions to delete and manage resources in your Azure subscription.
