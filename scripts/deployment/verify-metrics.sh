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

verify_alertmanager() {
    echo "Verifying Alertmanager configuration..."
    
    # Check if AlertManager is deployed
    if ! kubectl get pods -n "$MONITORING_NAMESPACE" -l app=alertmanager -o name | grep -q "pod/"; then
        echo "AlertManager not deployed, skipping verification"
        return 0
    fi
    
    # Get Alertmanager pod
    local alertmanager_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].metadata.name}')
    
    # Check AlertManager API health
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$alertmanager_pod" -- curl -s localhost:9093/-/healthy | grep -q "OK"; then
        handle_error 112 "AlertManager health check failed"
        return 1
    fi
    
    # Verify AlertManager configuration
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$alertmanager_pod" -- curl -s localhost:9093/api/v1/status | grep -q "config"; then
        handle_error 113 "AlertManager configuration check failed"
        return 1
    fi
    
    # Check if Besu-specific receivers are configured
    if ! kubectl get configmap -n "$MONITORING_NAMESPACE" alertmanager-config -o yaml | grep -q "besu"; then
        handle_error 114 "Besu alerts receivers not configured in AlertManager"
        return 1
    fi
    
    log_audit "alertmanager_verified" "AlertManager verification completed"
    return 0
}

verify_metrics_retention() {
    echo "Verifying metrics retention configuration..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check retention configuration
    local retention_config=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/status/config | grep "retention")
    
    if ! echo "$retention_config" | grep -q "retention"; then
        echo "Warning: Metrics retention not explicitly configured"
        log_audit "metrics_retention_warning" "Metrics retention not explicitly configured"
    else
        echo "Metrics retention configured: $retention_config"
        log_audit "metrics_retention_verified" "Metrics retention configuration verified"
    fi
    
    # Check storage configuration
    local storage_size=$(kubectl get pvc -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].spec.resources.requests.storage}')
    
    if [[ -z "$storage_size" ]]; then
        handle_error 115 "Prometheus storage not configured with PVC"
        return 1
    else
        echo "Prometheus storage size: $storage_size"
    fi
    
    log_audit "metrics_storage_verified" "Metrics storage configuration verified"
    return 0
}

verify_dashboard_details() {
    echo "Verifying Grafana dashboard details..."
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    # Get dashboard ID for Besu dashboard
    local dashboard_id=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s "localhost:${GRAFANA_PORT}/api/search?query=besu" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [[ -z "$dashboard_id" ]]; then
        handle_error 116 "Could not find Besu dashboard ID"
        return 1
    fi
    
    # Check dashboard details
    local dashboard_json=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s "localhost:${GRAFANA_PORT}/api/dashboards/uid/$dashboard_id")
    
    # Verify essential panels exist
    local required_panels=(
        "Blockchain Height"
        "Peer Count"
        "CPU Usage"
        "Memory Usage"
        "Transaction Pool"
    )
    
    for panel in "${required_panels[@]}"; do
        if ! echo "$dashboard_json" | grep -q "$panel"; then
            handle_error 117 "Required panel '$panel' not found in Besu dashboard"
            return 1
        fi
    done
    
    log_audit "dashboard_details_verified" "Grafana dashboard details verification completed"
    return 0
}

verify_historical_data() {
    echo "Verifying historical data availability..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check data for last 24 hours
    local query="count_over_time(besu_blockchain_height[24h]) > 0"
    local result=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=$query" "localhost:${PROMETHEUS_PORT}/api/v1/query")
    
    if ! echo "$result" | grep -q '"value":\[.*,1'; then
        echo "Warning: No historical blockchain height data found for the last 24 hours"
        log_audit "historical_data_warning" "No historical blockchain height data for last 24 hours"
    else
        log_audit "historical_data_verified" "Historical blockchain height data verified"
    fi
    
    return 0
}

verify_notification_templates() {
    echo "Verifying notification templates..."
    
    # Check if templates ConfigMap exists
    if ! kubectl get configmap -n "$MONITORING_NAMESPACE" prometheus-notification-templates &>/dev/null; then
        echo "Warning: Notification templates ConfigMap not found"
        log_audit "notification_templates_warning" "Notification templates ConfigMap not found"
        return 0
    fi
    
    # Check for Besu notification templates
    if ! kubectl get configmap -n "$MONITORING_NAMESPACE" prometheus-notification-templates -o yaml | grep -q "besu"; then
        handle_error 118 "Besu notification templates not found"
        return 1
    fi
    
    # Verify specific template elements
    local template_content=$(kubectl get configmap -n "$MONITORING_NAMESPACE" prometheus-notification-templates -o jsonpath='{.data.*.tmpl}')
    
    local required_elements=(
        "summary"
        "description"
        "severity"
        "runbook_url"
    )
    
    for element in "${required_elements[@]}"; do
        if ! echo "$template_content" | grep -q "$element"; then
            handle_error 119 "Required template element '$element' not found"
            return 1
        fi
    done
    
    log_audit "notification_templates_verified" "Notification templates verification completed"
    return 0
}

verify_scrape_intervals() {
    echo "Verifying metric scrape intervals..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Get scrape configs
    local scrape_configs=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/status/config | grep -A 10 "scrape_interval")
    
    # Check if Besu targets have appropriate scrape interval (should be <= 60s)
    local besu_scrape_interval=$(echo "$scrape_configs" | grep -A 10 "besu" | grep "scrape_interval" | head -1 | grep -o "[0-9]\+s")
    
    if [[ -z "$besu_scrape_interval" ]]; then
        echo "Warning: Could not determine Besu scrape interval"
        log_audit "scrape_interval_warning" "Could not determine Besu scrape interval"
    else
        # Extract numeric value from interval string (e.g., "15s" -> 15)
        local interval_value=$(echo "$besu_scrape_interval" | sed 's/s//')
        
        if [[ "$interval_value" -gt 60 ]]; then
            handle_error 120 "Besu scrape interval too long: ${besu_scrape_interval} (should be <= 60s)"
            return 1
        else
            echo "Besu scrape interval: ${besu_scrape_interval}"
        fi
    fi
    
    log_audit "scrape_intervals_verified" "Metric scrape intervals verification completed"
    return 0
}

verify_monitoring_performance() {
    echo "Verifying monitoring system performance..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Check Prometheus memory usage
    local prometheus_memory_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=process_resident_memory_bytes/1024/1024" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
    
    echo "Prometheus memory usage: ${prometheus_memory_usage} MB"
    
    # Check Prometheus CPU usage
    local prometheus_cpu_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=rate(process_cpu_seconds_total[5m])*100" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
    
    echo "Prometheus CPU usage: ${prometheus_cpu_usage}%"
    
    # Check Prometheus storage usage
    local prometheus_storage_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=prometheus_tsdb_storage_blocks_bytes/1024/1024/1024" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
    
    echo "Prometheus storage usage: ${prometheus_storage_usage} GB"
    
    # Alert if resource usage is too high
    if [[ $(echo "$prometheus_memory_usage > 2048" | bc -l) -eq 1 ]]; then
        echo "Warning: Prometheus memory usage is high (${prometheus_memory_usage} MB)"
        log_audit "prometheus_high_memory" "Prometheus memory usage is high: ${prometheus_memory_usage} MB"
    fi
    
    if [[ $(echo "$prometheus_cpu_usage > 80" | bc -l) -eq 1 ]]; then
        echo "Warning: Prometheus CPU usage is high (${prometheus_cpu_usage}%)"
        log_audit "prometheus_high_cpu" "Prometheus CPU usage is high: ${prometheus_cpu_usage}%"
    fi
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    # Check Grafana resources
    local grafana_resources=$(kubectl get pod -n "$MONITORING_NAMESPACE" "$grafana_pod" -o jsonpath='{.spec.containers[0].resources}')
    
    echo "Grafana resources configuration: $grafana_resources"
    
    log_audit "monitoring_performance_verified" "Monitoring system performance verification completed"
    return 0
}

generate_monitoring_report() {
    echo "Generating monitoring system report..."
    local report_file="${LOG_DIR}/monitoring_report_$(date +%Y%m%d_%H%M%S).json"
    local region=$1
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    # Collect metrics count
    local metrics_count=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/label/__name__/values | grep -o '"result":\[.*\]' | tr -d '[]{}"result:' | tr ',' '\n' | wc -l)
    
    # Collect targets count
    local targets_count=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/targets | grep -o '"activeTargets":\[.*\]' | tr -d '[]{}"activeTargets:' | tr ',' '\n' | grep -c "instance")
    
    # Collect alert rules count
    local rules_count=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/rules | grep -c "name")
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    # Collect dashboards count
    local dashboards_count=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s localhost:${GRAFANA_PORT}/api/search | grep -c "id")
    
    # Generate report JSON
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "region": "$region",
    "prometheus": {
        "status": "healthy",
        "metrics_count": $metrics_count,
        "targets_count": $targets_count,
        "alert_rules_count": $rules_count,
        "version": "$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s localhost:${PROMETHEUS_PORT}/api/v1/status/buildinfo | grep -o '"version":"[^"]*' | cut -d'"' -f4)"
    },
    "grafana": {
        "status": "healthy",
        "dashboards_count": $dashboards_count,
        "version": "$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s localhost:${GRAFANA_PORT}/api/health | grep -o '"version":"[^"]*' | cut -d'"' -f4)"
    },
    "besu_metrics": {
        "available": true,
        "essential_metrics_present": true
    },
    "performance": {
        "prometheus_memory_mb": "$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=process_resident_memory_bytes/1024/1024" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')",
        "prometheus_cpu_percent": "$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=rate(process_cpu_seconds_total[5m])*100" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')",
        "prometheus_storage_gb": "$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=prometheus_tsdb_storage_blocks_bytes/1024/1024/1024" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')"
    }
}
EOF
    
    echo "Monitoring report generated: $report_file"
    log_audit "monitoring_report_generated" "Monitoring system report generated for ${region}"
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
    verify_servicemonitors && \
    verify_alertmanager && \
    verify_metrics_retention && \
    verify_dashboard_details && \
    verify_historical_data && \
    verify_notification_templates && \
    verify_scrape_intervals && \
    verify_monitoring_performance
    
    if [ $? -eq 0 ]; then
        echo "✅ Monitoring verification successful for $region"
        log_audit "monitoring_verification_success" "Monitoring verification completed for ${region}"
        
        # Generate detailed monitoring report
        generate_monitoring_report "$region"
    else
        echo "❌ Monitoring verification failed for $region"
        echo "$region" >> "$FAILED_REGIONS_LOG"
        handle_error 111 "Monitoring verification failed for ${region}"
    fi
done < regions.txt

# Final status check - Fixed the bug by removing 'local' keyword
if [ -s "$FAILED_REGIONS_LOG" ]; then
    echo "❌ Monitoring verification failed in some regions:"
    cat "$FAILED_REGIONS_LOG"
    
    # Count failed regions
    failed_count=$(wc -l < "$FAILED_REGIONS_LOG")
    total_count=$(wc -l < regions.txt)
    success_rate=$(( (total_count - failed_count) * 100 / total_count ))
    
    echo "Success rate: $success_rate% ($((total_count - failed_count))/$total_count regions verified successfully)"
    log_audit "monitoring_verification_partial_failure" "Monitoring verification failed in some regions. Success rate: $success_rate%"
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