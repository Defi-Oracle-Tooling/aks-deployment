# Cleanup Architecture

## Overview
This document describes the unified cleanup architecture implemented across the deployment scripts.

## Implementation
The cleanup functionality is centralized in `scripts/deployment/deployment-utils.sh` and provides a consistent way to clean up resources across different deployment scenarios.

## Function Signature
The `cleanup_resources` function supports two modes:

1. **Resource Group Level Cleanup**
   ```bash
   cleanup_resources <region>
   ```
   This mode is used by `deploy.sh` to clean up an entire resource group for a failed region.

2. **Specific Resource Cleanup**
   ```bash
   cleanup_resources <resource_group> <resource_name> <resource_type> <namespace>
   ```
   This mode is used by `rollback.sh` to clean up specific resources.

## Usage in Scripts
- **deploy.sh**: Uses resource group level cleanup for failed regions
- **rollback.sh**: Uses specific resource cleanup for individual resources

## Logging
All cleanup operations are logged to:
- Console output for immediate feedback
- `audit.log` for traceability and auditing purposes

## Error Handling
The cleanup function includes error handling to ensure proper usage and logs any issues encountered during the cleanup process.

## Integration with Other Processes
The cleanup mechanism is part of a larger error handling strategy that includes:
1. Detailed error logging
2. Automated retry mechanisms
3. Rollback capabilities
4. Alerting and notifications

## Future Enhancements
Potential improvements to the cleanup architecture:
1. Add support for batched cleanup operations
2. Implement parallel cleanup for large-scale deployments
3. Add resource dependency tracking to ensure proper cleanup order
