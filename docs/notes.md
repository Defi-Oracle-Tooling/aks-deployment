# Notes

## Overview
This document provides additional information and tips for running the deployment script.

## Tips
- Ensure you have the necessary permissions to create and manage AKS clusters.
- Review the log files for detailed information on the deployment process and any errors encountered.
- Use the retry mechanism to handle transient errors and ensure successful deployments.
- Use the cleanup mechanism to remove any partially created resources in case of deployment failures.
- Use the rollback mechanism to revert to the previous state in case of deployment failures.
- Use the notification mechanism to stay informed about the deployment status, including both successes and failures.

![Notes](images/notes.png)

## Notes
- Review the `failed_regions.log` file for detailed error messages and specific error codes from the Azure CLI.
- Ensure you have the necessary permissions to delete and manage resources in your Azure subscription.
