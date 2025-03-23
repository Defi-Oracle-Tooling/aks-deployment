#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/deployment/deployment-utils.sh"

# Initialize logging
setup_logging

# Constants
BACKUP_DIR="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
ETCD_BACKUP_DIR="${BACKUP_DIR}/etcd"
CONFIG_BACKUP_DIR="${BACKUP_DIR}/config"

# Create backup directories
mkdir -p "$ETCD_BACKUP_DIR" "$CONFIG_BACKUP_DIR"

# Function to backup cluster configuration
backup_cluster_config() {
    local region=$1
    local cluster_name="besu-aks-${region}"
    local resource_group="besu-network-${region}"

    echo "Backing up cluster configuration for ${cluster_name}..."
    az aks show --name "$cluster_name" \
        --resource-group "$resource_group" \
        > "${CONFIG_BACKUP_DIR}/${cluster_name}_config.json"
}

# Function to backup etcd data
backup_etcd() {
    local region=$1
    local cluster_name="besu-aks-${region}"
    local resource_group="besu-network-${region}"

    echo "Creating etcd snapshot for ${cluster_name}..."
    az aks command invoke \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --command "etcdctl snapshot save /tmp/etcd-snapshot.db" \
        --cluster-admin

    # Copy the snapshot locally
    kubectl cp kube-system/etcd-0:/tmp/etcd-snapshot.db \
        "${ETCD_BACKUP_DIR}/${cluster_name}_etcd_snapshot.db"
}

# Main backup process
main() {
    # Get all regions from config
    local regions=$(jq -r '.regions[].name' "$REGIONS_FILE")

    for region in $regions; do
        backup_cluster_config "$region"
        backup_etcd "$region"
    done

    # Create archive of backup
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
    
    echo "✅ Backup completed: ${BACKUP_DIR}.tar.gz"
    log_audit "backup_completed" "Cluster backup completed successfully"
}

# Execute main function
main "$@"
