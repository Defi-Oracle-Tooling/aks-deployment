#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MIN_VALIDATOR_COUNT=3

verify_cluster_health() {
    local region=$1
    
    echo "Verifying cluster health in $region..."
    
    # Check node status
    if ! kubectl get nodes | grep -q "Ready"; then
        handle_error 80 "Node health check failed in ${region}"
        return 1
    fi
    
    # Verify system pods
    for ns in kube-system monitoring $NAMESPACE; do
        if ! kubectl get pods -n "$ns" | grep -v "Running\|Completed"; then
            handle_error 81 "Pod health check failed in namespace ${ns}"
            return 1
        fi
    done
    
    log_audit "cluster_health_verified" "Cluster health verification completed in ${region}"
}

verify_besu_deployment() {
    echo "Verifying Besu deployment..."
    
    # Check validator pods
    local validator_count=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=besu-validator | grep Running | wc -l)
    if [ "$validator_count" -lt "$MIN_VALIDATOR_COUNT" ]; then
        handle_error 82 "Insufficient validator count: ${validator_count}/${MIN_VALIDATOR_COUNT}"
        return 1
    fi
    
    # Check validator services
    if ! kubectl get services -n "$NAMESPACE" -l app.kubernetes.io/name=besu-validator; then
        handle_error 83 "Validator services not found"
        return 1
    fi
    
    # Verify persistent volumes
    if ! kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=besu-validator; then
        handle_error 84 "Validator PVCs not found"
        return 1
    fi
    
    log_audit "besu_deployment_verified" "Besu deployment verification completed"
}

verify_network_policies() {
    echo "Verifying network policies..."
    
    # Check default deny policy
    if ! kubectl get networkpolicies -n "$NAMESPACE" default-deny-all; then
        handle_error 85 "Default deny network policy not found"
        return 1
    fi
    
    # Check Besu network policies
    if ! kubectl get networkpolicies -n "$NAMESPACE" allow-besu-p2p; then
        handle_error 86 "Besu P2P network policy not found"
        return 1
    fi
    
    # Check monitoring network policies
    if ! kubectl get networkpolicies -n "$NAMESPACE" allow-prometheus-metrics; then
        handle_error 87 "Prometheus metrics network policy not found"
        return 1
    fi
    
    log_audit "network_policies_verified" "Network policies verification completed"
}

verify_security_config() {
    echo "Verifying security configuration..."
    
    # Check pod security policies
    if ! kubectl get psp besu-restricted; then
        handle_error 88 "Pod security policy not found"
        return 1
    fi
    
    # Verify RBAC configuration
    for sa in validator bootnode rpc; do
        if ! kubectl get serviceaccount "besu-${sa}" -n "$NAMESPACE"; then
            handle_error 89 "Service account besu-${sa} not found"
            return 1
        fi
    done
    
    log_audit "security_config_verified" "Security configuration verification completed"
}

verify_monitoring() {
    echo "Verifying monitoring setup..."
    
    # Check Prometheus deployment
    if ! kubectl get pods -n monitoring -l app=prometheus-server | grep Running; then
        handle_error 90 "Prometheus deployment not healthy"
        return 1
    fi
    
    # Check Grafana deployment
    if ! kubectl get pods -n monitoring -l app=grafana | grep Running; then
        handle_error 91 "Grafana deployment not healthy"
        return 1
    fi
    
    # Verify ServiceMonitor
    if ! kubectl get servicemonitor -n "$NAMESPACE" besu-validator; then
        handle_error 92 "Besu validator ServiceMonitor not found"
        return 1
    fi
    
    log_audit "monitoring_verified" "Monitoring setup verification completed"
}

verify_besu_metrics() {
    echo "Verifying Besu metrics..."
    
    # Get validator pod
    local validator_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=besu-validator -o jsonpath='{.items[0].metadata.name}')
    
    # Check metrics endpoint
    if ! kubectl exec -n "$NAMESPACE" "$validator_pod" -c besu -- curl -s localhost:9545/metrics | grep -q "besu_"; then
        handle_error 93 "Besu metrics endpoint not responding"
        return 1
    fi
    
    log_audit "besu_metrics_verified" "Besu metrics verification completed"
}

# Main verification process
echo "Starting deployment verification process..."

while read -r region; do
    echo "Verifying deployment in $region..."
    
    # Get AKS credentials
    if ! az aks get-credentials \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --overwrite-existing; then
        handle_error 94 "Failed to get AKS credentials for ${region}"
        continue
    fi
    
    # Run verification steps
    verify_cluster_health "$region" && \
    verify_besu_deployment && \
    verify_network_policies && \
    verify_security_config && \
    verify_monitoring && \
    verify_besu_metrics
    
    if [ $? -eq 0 ]; then
        echo "✅ Deployment verification successful for $region"
        log_audit "verification_success" "Deployment verification completed for ${region}"
    else
        echo "❌ Deployment verification failed for $region"
        echo "$region" >> "$FAILED_REGIONS_LOG"
        handle_error 95 "Deployment verification failed for ${region}"
    fi
done < regions.txt

# Final status check
if [ -s "$FAILED_REGIONS_LOG" ]; then
    echo "❌ Deployment verification failed in some regions. Check $FAILED_REGIONS_LOG for details."
    exit 1
else
    echo "✅ Deployment verification completed successfully in all regions!"
    exit 0
fi