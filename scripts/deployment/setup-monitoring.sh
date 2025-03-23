#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Source the deployment utilities (includes configuration loading)
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Use the get_config_value function from the utility
PROMETHEUS_SCRAPE_INTERVAL=$(get_config_value "common.monitoring.prometheus.scrape_interval")
echo "Prometheus scrape interval: $PROMETHEUS_SCRAPE_INTERVAL"

# Load configuration paths
CONFIG_PATHS_FILE="${PROJECT_ROOT}/config/configuration_paths.json"
REGIONS_FILE=$(get_config_value "cloud_providers.azure.regions")
VM_FAMILIES_FILE=$(get_config_value "cloud_providers.azure.vm_families")
NETWORKS_FILE=$(get_config_value "cloud_providers.azure.networks")
STORAGE_FILE=$(get_config_value "cloud_providers.azure.storage")

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"
HELM_TIMEOUT="10m"

setup_monitoring_namespace() {
    echo "Creating monitoring namespace..."
    kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    log_audit "monitoring_namespace_created" "Monitoring namespace setup completed"
}

deploy_prometheus() {
    echo "Deploying Prometheus..."
    
    # Add prometheus-community helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Deploy Prometheus with custom values
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.retentionSize="45GB" \
        --timeout "$HELM_TIMEOUT" \
        --wait
    
    # Apply Besu metrics configuration
    kubectl apply -f "${PROJECT_ROOT}/monitoring/prometheus/besu-metrics.yml" -n "$MONITORING_NAMESPACE"
    
    # Apply alert rules
    kubectl apply -f "${PROJECT_ROOT}/monitoring/alerts/" -n "$MONITORING_NAMESPACE"
    
    log_audit "prometheus_deployed" "Prometheus deployment completed"
}

deploy_grafana() {
    echo "Deploying Grafana..."
    
    # Create ConfigMaps for dashboards
    kubectl create configmap besu-dashboards \
        --from-file="${PROJECT_ROOT}/monitoring/grafana/besu-dashboard.json" \
        -n "$MONITORING_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply Grafana configuration
    kubectl apply -f "${PROJECT_ROOT}/monitoring/grafana/provisioning/" -n "$MONITORING_NAMESPACE"
    
    log_audit "grafana_deployed" "Grafana deployment completed"
}

configure_service_monitors() {
    echo "Configuring ServiceMonitors..."
    
    # Apply ServiceMonitor for Besu validators
    kubectl apply -f "${PROJECT_ROOT}/infrastructure/helm-charts/besu-validator/templates/servicemonitor.yaml" \
        -n "$MONITORING_NAMESPACE"
    
    log_audit "service_monitors_configured" "ServiceMonitors configuration completed"
}

verify_monitoring_deployment() {
    echo "Verifying monitoring deployment..."
    
    # Wait for Prometheus pods
    kubectl wait --for=condition=ready pod \
        -l app=prometheus \
        -n "$MONITORING_NAMESPACE" \
        --timeout=300s
    
    # Wait for Grafana pods
    kubectl wait --for=condition=ready pod \
        -l app=grafana \
        -n "$MONITORING_NAMESPACE" \
        --timeout=300s
    
    # Run verification script
    "${PROJECT_ROOT}/scripts/deployment/verify-metrics.sh"
    
    log_audit "monitoring_verified" "Monitoring deployment verification completed"
}

# Main setup process
echo "Starting monitoring setup process..."

while read -r region; do
    echo "Setting up monitoring in $region..."
    
    # Get AKS credentials
    if ! az aks get-credentials \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --overwrite-existing; then
        handle_error 200 "Failed to get AKS credentials for ${region}"
        continue
    fi
    
    # Run setup steps
    setup_monitoring_namespace && \
    deploy_prometheus && \
    deploy_grafana && \
    configure_service_monitors && \
    verify_monitoring_deployment
    
    if [ $? -eq 0 ]; then
        echo "✅ Monitoring setup successful for $region"
        log_audit "monitoring_setup_success" "Monitoring setup completed for ${region}"
    else
        echo "❌ Monitoring setup failed for $region"
        echo "$region" >> "$FAILED_REGIONS_LOG"
        handle_error 201 "Monitoring setup failed for ${region}"
    fi
done < regions.txt

# Final status check
if [ -s "$FAILED_REGIONS_LOG" ]; then
    echo "❌ Monitoring setup failed in some regions. Check $FAILED_REGIONS_LOG for details."
    exit 1
else
    echo "✅ Monitoring setup completed successfully in all regions!"
    exit 0
fi