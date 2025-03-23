#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Create configuration paths JSON
cat <<EOF > ${PROJECT_ROOT}/config/configuration_paths.json
{
    "cloud_providers": {
        "azure": {
            "regions": "${PROJECT_ROOT}/config/cloud_providers/azure/azure_regions.json",
            "vm_families": "${PROJECT_ROOT}/config/cloud_providers/azure/azure_vm_families.json",
            "networks": "${PROJECT_ROOT}/config/cloud_providers/azure/azure_networks.json",
            "storage": "${PROJECT_ROOT}/config/cloud_providers/azure/azure_storage.json"
        },
        "aws": {
            "regions": "${PROJECT_ROOT}/config/cloud_providers/aws/aws_regions.json",
            "instance_types": "${PROJECT_ROOT}/config/cloud_providers/aws/aws_instance_types.json",
            "networks": "${PROJECT_ROOT}/config/cloud_providers/aws/aws_networks.json",
            "storage": "${PROJECT_ROOT}/config/cloud_providers/aws/aws_storage.json"
        },
        "gcp": {
            "regions": "${PROJECT_ROOT}/config/cloud_providers/gcp/gcp_regions.json",
            "machine_types": "${PROJECT_ROOT}/config/cloud_providers/gcp/gcp_machine_types.json",
            "networks": "${PROJECT_ROOT}/config/cloud_providers/gcp/gcp_networks.json",
            "storage": "${PROJECT_ROOT}/config/cloud_providers/gcp/gcp_storage.json"
        }
    },
    "common": {
        "logging": "${PROJECT_ROOT}/config/common/logging.json",
        "monitoring": "${PROJECT_ROOT}/config/common/monitoring.json",
        "security": "${PROJECT_ROOT}/config/common/security.json"
    },
    "environments": {
        "production": "${PROJECT_ROOT}/config/environments/production.json",
        "staging": "${PROJECT_ROOT}/config/environments/staging.json",
        "development": "${PROJECT_ROOT}/config/environments/development.json"
    },
    "github": {
        "actions": "${PROJECT_ROOT}/config/github/github_actions.json",
        "secrets": "${PROJECT_ROOT}/config/github/github_secrets.json"
    }
}
EOF

echo "Configuration paths generated successfully."