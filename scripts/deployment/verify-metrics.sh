#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000

verify_prometheus_health() {
    echo "Verifying Prometheus health..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check Prometheus API health
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/-/healthy | grep -q "OK"; then
        handle_error 100 "Prometheus health check failed"
        return 1
    fi
    
    # Verify Prometheus targets
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/targets" | grep -q "besu"; then
        handle_error 101 "Besu targets not found in Prometheus"
        return 1
    fi
    
    log_audit "prometheus_health_verified" "Prometheus health verification completed"
}

verify_grafana_health() {
    echo "Verifying Grafana health..."
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    # Check Grafana API health
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s localhost:${GRAFANA_PORT}/api/health | grep -q "ok"; then
        handle_error 102 "Grafana health check failed"
        return 1
    fi
    
    # Verify Grafana datasources
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s "localhost:${GRAFANA_PORT}/api/datasources" -H "X-Grafana-Org-Id: 1" | grep -q "prometheus"; then
        handle_error 103 "Prometheus datasource not found in Grafana"
        return 1
    fi
    
    # Check Besu dashboard exists
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s "localhost:${GRAFANA_PORT}/api/search?query=besu" | grep -q "Besu"; then
        handle_error 104 "Besu dashboard not found in Grafana"
        return 1
    fi
    
    log_audit "grafana_health_verified" "Grafana health verification completed"
}

verify_besu_metrics_collection() {
    echo "Verifying Besu metrics collection..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check for essential Besu metrics
    local required_metrics=(
        "besu_blockchain_height"
        "besu_peers"
        "besu_synchronizer_block_height"
        "besu_network_peer_count"
        "process_cpu_seconds_total"
        "jvm_memory_bytes_used"
    )
    
    for metric in "${required_metrics[@]}"; do
        if ! kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=${metric}" | grep -q "result"; then
            handle_error 105 "Required metric ${metric} not found"
            return 1
        fi
    done
    
    log_audit "besu_metrics_collection_verified" "Besu metrics collection verification completed"
}

verify_alert_rules() {
    echo "Verifying Prometheus alert rules..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check alert rules configuration
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/rules" | grep -q "besu"; then
        handle_error 106 "Besu alert rules not found"
        return 1
    fi
    
    # Verify specific alert rules exist
    local required_alerts=(
        "BesuNodeDown"
        "BesuPeerCountLow"
        "BesuBlockHeightStuck"
        "BesuHighMemoryUsage"
        "BesuHighCPUUsage"
    )
    
    local rules_json=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/rules")
    
    for alert in "${required_alerts[@]}"; do
        if ! echo "$rules_json" | grep -q "$alert"; then
            handle_error 107 "Required alert rule ${alert} not found"
            return 1
        fi
    done
    
    log_audit "alert_rules_verified" "Alert rules verification completed"
}

verify_servicemonitors() {
    echo "Verifying ServiceMonitors..."
    
    # Check Besu ServiceMonitor
    if ! kubectl get servicemonitor -n "$NAMESPACE" besu-validator; then
        handle_error 108 "Besu validator ServiceMonitor not found"
        return 1
    fi
    
    # Verify ServiceMonitor configuration
    if ! kubectl get servicemonitor -n "$NAMESPACE" besu-validator -o yaml | grep -q "metrics"; then
        handle_error 109 "Besu validator ServiceMonitor missing metrics endpoint configuration"
        return 1
    fi
    
    log_audit "servicemonitors_verified" "ServiceMonitors verification completed"
}

# Main monitoring verification process
echo "Starting monitoring verification process..."

# Initialize failed regions log
FAILED_REGIONS_LOG="failed_regions_monitoring.log"
> "$FAILED_REGIONS_LOG"

while read -r region; do
    echo "Verifying monitoring in $region..."
    
    # Get AKS credentials
    if ! az aks get-credentials \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --overwrite-existing; then
        handle_error 110 "Failed to get AKS credentials for ${region}"
        continue
    fi
    
    # Run verification steps
    verify_prometheus_health && \
    verify_grafana_health && \
    verify_besu_metrics_collection && \
    verify_alert_rules && \
    verify_servicemonitors
    
    if [ $? -eq 0 ]; then
        echo "✅ Monitoring verification successful for $region"
        log_audit "monitoring_verification_success" "Monitoring verification completed for ${region}"
    else
        echo "❌ Monitoring verification failed for $region"
        echo "$region" >> "$FAILED_REGIONS_LOG"
        handle_error 111 "Monitoring verification failed for ${region}"
    fi
done < regions.txt

# Final status check
if [ -s "$FAILED_REGIONS_LOG" ]; then
    echo "❌ Monitoring verification failed in some regions:"
    cat "$FAILED_REGIONS_LOG"
    log_audit "monitoring_verification_partial_failure" "Monitoring verification failed in some regions"
    exit 1
else
    echo "✅ Monitoring verification completed successfully in all regions"
    log_audit "monitoring_verification_complete_success" "Monitoring verification completed successfully in all regions"
    rm -f "$FAILED_REGIONS_LOG"
    exit 0
fi

# Cleanup function to be called on script exit
cleanup() {
    echo "Cleaning up..."
    # Remove any temporary files or resources
    rm -f "$FAILED_REGIONS_LOG"
    log_audit "cleanup_completed" "Cleanup completed"
}

# Set trap for cleanup on script exit
trap cleanup EXIT