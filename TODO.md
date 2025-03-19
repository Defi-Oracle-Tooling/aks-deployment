# TODO List

## High Priority
1. **State Management for Deployments**
   - ~~Implement a success-state file to record successfully deployed regions.~~
   - ~~Modify the deployment script to skip regions that are already deployed successfully.~~
   - ~~Include a pre-deployment check to verify if the cluster exists and is healthy before proceeding.~~

2. **Automated Testing**
   - ~~Integrate unit/integration tests in the CI/CD pipeline to validate changes to ARM templates and scripts before deployment.~~

## Medium Priority
1. **Error Handling and Logging**
   - ~~Enhance error logging to provide more detailed information about deployment failures.~~
   - ~~Implement a retry mechanism for failed deployments with exponential backoff.~~

2. **Documentation**
   - ~~Update the README file to include new features and usage instructions.~~
   - ~~Document the deployment process and any prerequisites in detail.~~

## Low Priority
1. **Code Refactoring**
   - ~~Refactor the deployment script for better readability and maintainability.~~
   - ~~Modularize the script to separate different functionalities into functions.~~

2. **Performance Optimization**
   - ~~Optimize the deployment script to reduce execution time.~~
   - ~~Investigate and implement any potential performance improvements.~~

## Additional Enhancements
1. **Logging for Successful Deployments**
   - ~~Add logging for successful deployments to better track and audit the deployment process.~~

2. **Cleanup Mechanism**
   - ~~Implement a cleanup mechanism to remove any partially created resources in case of deployment failures.~~

3. **Detailed Error Messages**
   - ~~Enhance error messages to include more details about the failure, such as specific error codes or messages from the Azure CLI.~~

4. **Notification Mechanism**
   - ~~Integrate a notification mechanism (e.g., email, Slack) to notify the team about the deployment status, including both successes and failures.~~

5. **More Unit/Integration Tests**
   - ~~Expand the unit/integration tests to cover more edge cases and scenarios to ensure the robustness of the deployment process.~~

6. **Support for Rollback**
   - ~~Implement a rollback mechanism to revert to the previous state in case of deployment failures.~~

7. **Documentation for New Features**
   - ~~Update the documentation to include any new features or changes made to the deployment process, such as the logging, cleanup, and notification mechanisms.~~

![TODO Workflow](docs/images/todo_workflow.png)
