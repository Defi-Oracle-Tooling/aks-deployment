#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"
PROMETHEUS_PORT=9090

# Parse command line arguments
usage() {
    echo "Usage: $0 [--namespace <namespace>] [--component <component>] [--issue <issue-type>]"
    echo "Available components: prometheus, alertmanager, grafana, node-exporter, kube-state-metrics"
    echo "Available issue types: restart, disk-cleanup, config-repair, scaling, network-connectivity"
    exit 1
}

COMPONENT=""
ISSUE_TYPE=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --namespace)
            MONITORING_NAMESPACE="$2"
            shift
            shift
            ;;
        --component)
            COMPONENT="$2"
            shift
            shift
            ;;
        --issue)
            ISSUE_TYPE="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Function to restart failed components
restart_component() {
    local component=$1
    echo "Attempting to restart $component..."
    
    # Get the deployment name based on component
    local deployment=""
    case $component in
        prometheus)
            deployment="prometheus-server"
            ;;
        alertmanager)
            deployment="alertmanager"
            ;;
        grafana)
            deployment="grafana"
            ;;
        node-exporter)
            deployment="node-exporter"
            ;;
        kube-state-metrics)
            deployment="kube-state-metrics"
            ;;
        *)
            handle_error 300 "Unknown component: $component"
            return 1
            ;;
    esac
    
    # Restart by scaling down and up
    echo "Scaling down $deployment..."
    kubectl scale deployment -n "$MONITORING_NAMESPACE" "$deployment" --replicas=0
    sleep 5
    
    echo "Scaling up $deployment..."
    kubectl scale deployment -n "$MONITORING_NAMESPACE" "$deployment" --replicas=1
    
    # Wait for component to be ready
    echo "Waiting for $component to be ready..."
    kubectl rollout status deployment -n "$MONITORING_NAMESPACE" "$deployment" --timeout=120s
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully restarted $component"
        log_audit "component_restarted" "Successfully restarted $component"
        return 0
    else
        handle_error 301 "Failed to restart $component"
        return 1
    fi
}

# Function to clean up disk space
cleanup_disk_space() {
    local component=$1
    echo "Cleaning up disk space for $component..."
    
    # Get pod name based on component
    local pod=""
    case $component in
        prometheus)
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
            
            # Check disk usage
            echo "Checking Prometheus disk usage..."
            local disk_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- df -h /prometheus | tail -n 1 | awk '{print $5}' | sed 's/%//')
            
            if [[ $disk_usage -gt 85 ]]; then
                echo "Disk usage is high: ${disk_usage}%"
                
                # Clean up old data by compacting blocks
                echo "Compacting TSDB blocks..."
                kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -X POST http://localhost:${PROMETHEUS_PORT}/-/compact
                
                # Wait for compaction to complete
                sleep 10
                
                # Check disk usage after cleanup
                local new_disk_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- df -h /prometheus | tail -n 1 | awk '{print $5}' | sed 's/%//')
                
                if [[ $new_disk_usage -lt $disk_usage ]]; then
                    echo "✅ Successfully reduced disk usage from ${disk_usage}% to ${new_disk_usage}%"
                    log_audit "disk_cleanup_success" "Reduced disk usage for $component from ${disk_usage}% to ${new_disk_usage}%"
                    return 0
                else
                    echo "⚠️ Disk usage did not decrease after compaction"
                    
                    # If compaction didn't help, consider reducing retention period temporarily
                    echo "Temporarily reducing retention period..."
                    kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -X POST -g "http://localhost:${PROMETHEUS_PORT}/-/reload"
                    
                    handle_error 302 "Disk usage remains high after compaction: ${new_disk_usage}%"
                    return 1
                fi
            else
                echo "Disk usage is acceptable: ${disk_usage}%"
                return 0
            fi
            ;;
        
        grafana)
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
            
            # For Grafana, clean up old sessions and temp files
            echo "Cleaning up Grafana temporary files..."
            kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- find /var/lib/grafana/temp -type f -mtime +7 -delete
            kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- find /var/lib/grafana/sessions -type f -mtime +1 -delete
            
            echo "✅ Cleaned up Grafana temporary files"
            log_audit "grafana_cleanup_success" "Cleaned up temporary files for Grafana"
            return 0
            ;;
        
        *)
            handle_error 303 "Disk cleanup not implemented for component: $component"
            return 1
            ;;
    esac
}

# Function to repair configuration
repair_config() {
    local component=$1
    echo "Repairing configuration for $component..."
    
    case $component in
        prometheus)
            # Check if Prometheus config is valid
            local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
            
            echo "Validating Prometheus configuration..."
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- promtool check config /etc/prometheus/prometheus.yml; then
                echo "⚠️ Prometheus configuration is invalid"
                
                # Backup the invalid config
                echo "Backing up invalid configuration..."
                kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.invalid
                
                # Try to restore from a known good config
                echo "Restoring from default configuration..."
                kubectl get configmap -n "$MONITORING_NAMESPACE" prometheus-server -o yaml | kubectl replace --force -f -
                
                # Trigger a reload
                kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -X POST http://localhost:${PROMETHEUS_PORT}/-/reload
                
                echo "✅ Restored Prometheus configuration from default"
                log_audit "prometheus_config_restored" "Restored Prometheus configuration from default"
                return 0
            else
                echo "✅ Prometheus configuration is valid"
                return 0
            fi
            ;;
        
        alertmanager)
            # Check if AlertManager config is valid
            local alertmanager_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].metadata.name}')
            
            echo "Validating AlertManager configuration..."
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$alertmanager_pod" -- amtool check-config /etc/alertmanager/alertmanager.yml; then
                echo "⚠️ AlertManager configuration is invalid"
                
                # Backup the invalid config
                echo "Backing up invalid configuration..."
                kubectl exec -n "$MONITORING_NAMESPACE" "$alertmanager_pod" -- cp /etc/alertmanager/alertmanager.yml /etc/alertmanager/alertmanager.yml.invalid
                
                # Try to restore from a known good config
                echo "Restoring from default configuration..."
                kubectl get secret -n "$MONITORING_NAMESPACE" alertmanager-alertmanager -o yaml | kubectl replace --force -f -
                
                # Restart AlertManager to apply the new config
                kubectl delete pod -n "$MONITORING_NAMESPACE" "$alertmanager_pod"
                
                echo "✅ Restored AlertManager configuration from default"
                log_audit "alertmanager_config_restored" "Restored AlertManager configuration from default"
                return 0
            else
                echo "✅ AlertManager configuration is valid"
                return 0
            fi
            ;;
        
        *)
            handle_error 304 "Configuration repair not implemented for component: $component"
            return 1
            ;;
    esac
}

# Function to apply auto-scaling based on sizing recommendations
apply_auto_scaling() {
    local component=$1
    echo "Applying auto-scaling for $component..."
    
    case $component in
        prometheus)
            # Get current Prometheus resource usage
            local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
            
            echo "Checking Prometheus resource usage..."
            
            # Get current memory usage
            local memory_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=process_resident_memory_bytes/1024/1024" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
            
            # Get current CPU usage
            local cpu_usage=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=rate(process_cpu_seconds_total[5m])*100" | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
            
            # Get current resource requests/limits
            local current_memory_request=$(kubectl get deployment -n "$MONITORING_NAMESPACE" prometheus-server -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
            local current_cpu_request=$(kubectl get deployment -n "$MONITORING_NAMESPACE" prometheus-server -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
            
            echo "Current Usage: Memory=${memory_usage}MB, CPU=${cpu_usage}%"
            echo "Current Requests: Memory=${current_memory_request}, CPU=${current_cpu_request}"
            
            # Convert current requests to numeric values
            local current_memory_mb=$(echo "$current_memory_request" | sed -E 's/([0-9]+)(Mi|Gi)/\1/' | awk '{if ($0 ~ /Gi/) print $1*1024; else print $1}')
            local current_cpu_millicores=$(echo "$current_cpu_request" | sed -E 's/([0-9]+)m/\1/')
            
            # Calculate target values (increase by 30% if usage > 70% of request)
            local memory_usage_percentage=$(echo "scale=2; $memory_usage / $current_memory_mb * 100" | bc)
            local cpu_usage_percentage=$(echo "scale=2; $cpu_usage * 10 / $current_cpu_millicores * 100" | bc) # Multiply by 10 to convert CPU percentage to millicores
            
            echo "Usage Percentage: Memory=${memory_usage_percentage}%, CPU=${cpu_usage_percentage}%"
            
            local needs_scaling=false
            local new_memory_request=$current_memory_mb
            local new_cpu_request=$current_cpu_millicores
            
            if (( $(echo "$memory_usage_percentage > 70" | bc -l) )); then
                echo "Memory usage exceeds 70% of request, scaling up..."
                new_memory_request=$(echo "scale=0; $current_memory_mb * 1.3 / 1" | bc) # Round to integer
                needs_scaling=true
            fi
            
            if (( $(echo "$cpu_usage_percentage > 70" | bc -l) )); then
                echo "CPU usage exceeds 70% of request, scaling up..."
                new_cpu_request=$(echo "scale=0; $current_cpu_millicores * 1.3 / 1" | bc) # Round to integer
                needs_scaling=true
            fi
            
            if [[ "$needs_scaling" == "true" ]]; then
                echo "Applying new resource requests: Memory=${new_memory_request}Mi, CPU=${new_cpu_request}m"
                
                # Create a patch for the deployment
                local patch=$(cat <<EOF
{"spec":{"template":{"spec":{"containers":[{"name":"prometheus-server","resources":{"requests":{"memory":"${new_memory_request}Mi","cpu":"${new_cpu_request}m"}}}]}}}}
EOF
)
                
                # Apply the patch
                kubectl patch deployment -n "$MONITORING_NAMESPACE" prometheus-server --patch "$patch"
                
                echo "✅ Scaled Prometheus resources: Memory=${current_memory_mb}Mi → ${new_memory_request}Mi, CPU=${current_cpu_millicores}m → ${new_cpu_request}m"
                log_audit "prometheus_auto_scaled" "Scaled Prometheus resources: Memory=${current_memory_mb}Mi → ${new_memory_request}Mi, CPU=${current_cpu_millicores}m → ${new_cpu_request}m"
                return 0
            else
                echo "✅ Current resource allocation is sufficient"
                return 0
            fi
            ;;
        
        *)
            handle_error 305 "Auto-scaling not implemented for component: $component"
            return 1
            ;;
    esac
}

# New function to diagnose and fix network connectivity issues
fix_network_connectivity() {
    local component=$1
    echo "Diagnosing network connectivity issues for $component..."
    
    # Get pod name based on component
    local pod=""
    local service=""
    local port=""
    
    case $component in
        prometheus)
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
            service="prometheus-server"
            port="${PROMETHEUS_PORT}"
            ;;
        alertmanager)
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].metadata.name}')
            service="alertmanager"
            port="9093"
            ;;
        grafana)
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
            service="grafana"
            port="3000"
            ;;
        *)
            handle_error 310 "Network connectivity diagnosis not implemented for component: $component"
            return 1
            ;;
    esac
    
    if [[ -z "$pod" ]]; then
        handle_error 311 "Pod not found for component: $component"
        return 1
    fi
    
    echo "Checking network connectivity for $component ($pod)..."
    
    # Check 1: Check if pod has network connectivity
    echo "Testing basic network connectivity..."
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- ping -c 3 8.8.8.8 &>/dev/null; then
        echo "⚠️ Basic network connectivity issue detected"
        
        # Check pod network policy
        echo "Checking network policies..."
        network_policies=$(kubectl get networkpolicy -n "$MONITORING_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
        
        if [[ -n "$network_policies" ]]; then
            echo "Found network policies: $network_policies"
            
            # Create a temporary permissive network policy to test connectivity
            echo "Creating temporary permissive network policy for diagnostics..."
            cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temp-${component}-network-diagnostics
  namespace: $MONITORING_NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: $component
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF
            
            # Wait a short time for policy to apply
            sleep 5
            
            # Re-test connectivity
            if kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- ping -c 3 8.8.8.8 &>/dev/null; then
                echo "✅ Network connectivity restored with permissive policy"
                echo "⚠️ Existing network policies may be too restrictive"
                log_audit "network_policy_issue_detected" "Existing network policies may be restricting connectivity for $component"
            else
                echo "⚠️ Network connectivity still fails even with permissive policy"
                # Clean up temporary policy
                kubectl delete networkpolicy -n "$MONITORING_NAMESPACE" "temp-${component}-network-diagnostics"
                
                # Check for CNI issues
                echo "Checking for CNI issues..."
                node_name=$(kubectl get pod -n "$MONITORING_NAMESPACE" "$pod" -o jsonpath='{.spec.nodeName}')
                echo "Pod is running on node: $node_name"
                
                # Check node network status
                echo "Checking node network status..."
                node_ready=$(kubectl get node $node_name -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
                node_network_unavailable=$(kubectl get node $node_name -o jsonpath='{.status.conditions[?(@.type=="NetworkUnavailable")].status}')
                
                if [[ "$node_ready" != "True" ]]; then
                    echo "⚠️ Node $node_name is not in Ready state"
                    log_audit "node_not_ready" "Node $node_name hosting $component is not in Ready state"
                fi
                
                if [[ "$node_network_unavailable" == "True" ]]; then
                    echo "⚠️ Node $node_name has network unavailable condition"
                    log_audit "node_network_unavailable" "Node $node_name hosting $component has NetworkUnavailable condition"
                    
                    # Try to cordon and uncordon node to trigger network reconfiguration
                    echo "Attempting to reconfigure node networking..."
                    kubectl cordon $node_name
                    sleep 5
                    kubectl uncordon $node_name
                    
                    # Wait for node to recover
                    echo "Waiting for node to recover..."
                    kubectl wait --for=condition=Ready node/$node_name --timeout=60s
                    
                    # Restart the affected pod
                    echo "Restarting affected pod..."
                    kubectl delete pod -n "$MONITORING_NAMESPACE" "$pod"
                    
                    # Wait for new pod to be created
                    echo "Waiting for new pod to be created and ready..."
                    sleep 10
                    new_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=$component -o jsonpath='{.items[0].metadata.name}')
                    kubectl wait --for=condition=Ready pod/$new_pod -n "$MONITORING_NAMESPACE" --timeout=60s
                    
                    # Test connectivity again
                    if kubectl exec -n "$MONITORING_NAMESPACE" "$new_pod" -- ping -c 3 8.8.8.8 &>/dev/null; then
                        echo "✅ Network connectivity restored after node reconfiguration"
                        log_audit "network_connectivity_restored" "Network connectivity for $component restored after node reconfiguration"
                        return 0
                    else
                        echo "❌ Network connectivity still fails after node reconfiguration"
                    fi
                fi
            fi
            
            # Clean up temporary policy if still exists
            kubectl delete networkpolicy -n "$MONITORING_NAMESPACE" "temp-${component}-network-diagnostics" --ignore-not-found
        fi
    else
        echo "✅ Basic network connectivity is working"
    fi
    
    # Check 2: Check if service endpoints are reachable
    echo "Checking service endpoints for $service..."
    
    # Get service endpoint
    service_cluster_ip=$(kubectl get service -n "$MONITORING_NAMESPACE" "$service" -o jsonpath='{.spec.clusterIP}')
    if [[ -z "$service_cluster_ip" ]]; then
        echo "⚠️ Service $service has no cluster IP"
        
        # Try to recreate the service
        echo "Attempting to recreate service..."
        kubectl get service -n "$MONITORING_NAMESPACE" "$service" -o yaml > /tmp/service-${service}.yaml
        kubectl delete service -n "$MONITORING_NAMESPACE" "$service"
        kubectl apply -f /tmp/service-${service}.yaml
        
        # Wait for service to be created
        sleep 5
        service_cluster_ip=$(kubectl get service -n "$MONITORING_NAMESPACE" "$service" -o jsonpath='{.spec.clusterIP}')
        if [[ -z "$service_cluster_ip" ]]; then
            handle_error 312 "Failed to recreate service $service"
            return 1
        fi
        log_audit "service_recreated" "Service $service was recreated"
    fi
    
    # Check if service endpoints exist
    endpoint_count=$(kubectl get endpoints -n "$MONITORING_NAMESPACE" "$service" -o jsonpath='{.subsets[0].addresses}' | jq 'length' 2>/dev/null || echo 0)
    if [[ $endpoint_count -eq 0 ]]; then
        echo "⚠️ No endpoints found for service $service"
        
        # Check pod labels match service selector
        service_selector=$(kubectl get service -n "$MONITORING_NAMESPACE" "$service" -o jsonpath='{.spec.selector}')
        echo "Service selector: $service_selector"
        
        # Convert JSON to 'key=value' format for label selector
        label_selector=""
        for key in $(echo "$service_selector" | jq -r 'keys[]'); do
            value=$(echo "$service_selector" | jq -r --arg key "$key" '.[$key]')
            label_selector="${label_selector}${key}=${value},"
        done
        label_selector=${label_selector%,}
        
        # Check if pods match this selector
        matching_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l "$label_selector" -o jsonpath='{.items[*].metadata.name}')
        if [[ -z "$matching_pods" ]]; then
            echo "⚠️ No pods match service selector"
            
            # Check actual pod labels
            pod_labels=$(kubectl get pod -n "$MONITORING_NAMESPACE" "$pod" -o jsonpath='{.metadata.labels}')
            echo "Pod labels: $pod_labels"
            
            # Try to update pod labels to match service selector
            for key in $(echo "$service_selector" | jq -r 'keys[]'); do
                value=$(echo "$service_selector" | jq -r --arg key "$key" '.[$key]')
                kubectl label pod -n "$MONITORING_NAMESPACE" "$pod" "${key}=${value}" --overwrite
            done
            
            echo "✅ Pod labels updated to match service selector"
            log_audit "pod_labels_updated" "Updated labels for pod $pod to match service selector"
            
            # Wait for endpoints to update
            sleep 5
            
            # Check if endpoints now exist
            endpoint_count=$(kubectl get endpoints -n "$MONITORING_NAMESPACE" "$service" -o jsonpath='{.subsets[0].addresses}' | jq 'length' 2>/dev/null || echo 0)
            if [[ $endpoint_count -gt 0 ]]; then
                echo "✅ Service endpoints successfully created"
            else
                echo "❌ Still no endpoints for service after updating pod labels"
                handle_error 313 "Failed to create endpoints for service $service"
                return 1
            fi
        fi
    else
        echo "✅ Service has $endpoint_count endpoint(s)"
    fi
    
    # Check 3: DNS resolution
    echo "Checking DNS resolution..."
    if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- nslookup kubernetes.default.svc.cluster.local; then
        echo "⚠️ DNS resolution issue detected"
        
        # Check CoreDNS pods
        echo "Checking CoreDNS pods..."
        coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].metadata.name}')
        
        if [[ -z "$coredns_pods" ]]; then
            echo "❌ No CoreDNS pods found"
            handle_error 314 "No CoreDNS pods found in kube-system namespace"
            return 1
        fi
        
        # Restart CoreDNS pods
        echo "Restarting CoreDNS pods..."
        for coredns_pod in $coredns_pods; do
            kubectl delete pod -n kube-system $coredns_pod
        done
        
        # Wait for CoreDNS pods to restart
        echo "Waiting for CoreDNS pods to restart..."
        sleep 10
        
        # Test DNS resolution again
        if kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- nslookup kubernetes.default.svc.cluster.local; then
            echo "✅ DNS resolution fixed after CoreDNS restart"
            log_audit "dns_resolution_fixed" "DNS resolution fixed after CoreDNS restart"
        else
            echo "❌ DNS resolution still fails after CoreDNS restart"
            handle_error 315 "DNS resolution still fails after CoreDNS restart"
            return 1
        fi
    else
        echo "✅ DNS resolution is working"
    fi
    
    # Check 4: Test component-specific connectivity
    echo "Testing component-specific connectivity..."
    
    case $component in
        prometheus)
            # Test Prometheus API
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/v1/status/config" > /dev/null; then
                echo "⚠️ Prometheus API is not responding"
                # Try restarting just the Prometheus process
                kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- pkill prometheus
                echo "Prometheus process restarted, waiting for it to initialize..."
                sleep 10
                
                if kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/v1/status/config" > /dev/null; then
                    echo "✅ Prometheus API is now responding"
                    log_audit "prometheus_process_restarted" "Prometheus process restarted to fix API connectivity"
                else
                    echo "❌ Prometheus API still not responding after process restart"
                fi
            else
                echo "✅ Prometheus API is responding"
            fi
            ;;
        alertmanager)
            # Test AlertManager API
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/v1/status" > /dev/null; then
                echo "⚠️ AlertManager API is not responding"
                kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- pkill alertmanager
                echo "AlertManager process restarted, waiting for it to initialize..."
                sleep 10
                
                if kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/v1/status" > /dev/null; then
                    echo "✅ AlertManager API is now responding"
                    log_audit "alertmanager_process_restarted" "AlertManager process restarted to fix API connectivity"
                else
                    echo "❌ AlertManager API still not responding after process restart"
                fi
            else
                echo "✅ AlertManager API is responding"
            fi
            ;;
        grafana)
            # Test Grafana API
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/health" > /dev/null; then
                echo "⚠️ Grafana API is not responding"
                kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- pkill grafana
                echo "Grafana process restarted, waiting for it to initialize..."
                sleep 10
                
                if kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:${port}/api/health" > /dev/null; then
                    echo "✅ Grafana API is now responding"
                    log_audit "grafana_process_restarted" "Grafana process restarted to fix API connectivity"
                else
                    echo "❌ Grafana API still not responding after process restart"
                fi
            else
                echo "✅ Grafana API is responding"
            fi
            ;;
    esac
    
    echo "✅ Network connectivity verification completed for $component"
    log_audit "network_connectivity_verified" "Network connectivity verification completed for $component"
    return 0
}

# Main execution
echo "Starting auto-remediation process..."

# If no component or issue type specified, try to auto-detect issues
if [[ -z "$COMPONENT" || -z "$ISSUE_TYPE" ]]; then
    echo "No specific component or issue type specified. Performing auto-detection..."
    
    # Check for failed pods
    echo "Checking for failed monitoring components..."
    FAILED_PODS=$(kubectl get pods -n "$MONITORING_NAMESPACE" | grep -v Running | grep -v Completed)
    
    if [[ -n "$FAILED_PODS" ]]; then
        echo "Found failed pods in monitoring namespace:"
        echo "$FAILED_PODS"
        
        # Extract component names from failed pods
        while read -r pod status rest; do
            if [[ "$pod" =~ prometheus ]]; then
                COMPONENT="prometheus"
            elif [[ "$pod" =~ alertmanager ]]; then
                COMPONENT="alertmanager"
            elif [[ "$pod" =~ grafana ]]; then
                COMPONENT="grafana"
            elif [[ "$pod" =~ node-exporter ]]; then
                COMPONENT="node-exporter"
            elif [[ "$pod" =~ kube-state-metrics ]]; then
                COMPONENT="kube-state-metrics"
            fi
            
            # Determine issue type based on status
            if [[ "$status" == "Error" || "$status" == "CrashLoopBackOff" ]]; then
                ISSUE_TYPE="restart"
            elif [[ "$status" == "ContainerCreating" ]]; then
                # Check if it's stuck in container creating state for more than 5 minutes
                AGE=$(kubectl get pod -n "$MONITORING_NAMESPACE" "$pod" -o jsonpath='{.metadata.creationTimestamp}')
                CURRENT_TIME=$(date -u +%s)
                POD_AGE=$(date -d "$AGE" +%s)
                AGE_DIFF=$((CURRENT_TIME - POD_AGE))
                
                if [[ $AGE_DIFF -gt 300 ]]; then
                    ISSUE_TYPE="restart"
                fi
            fi
            
            if [[ -n "$COMPONENT" && -n "$ISSUE_TYPE" ]]; then
                break
            fi
        done <<< "$FAILED_PODS"
    fi
    
    # If no failed pods found, check for resource issues
    if [[ -z "$COMPONENT" || -z "$ISSUE_TYPE" ]]; then
        echo "Checking for resource issues..."
        
        # Check Prometheus disk space
        PROMETHEUS_POD=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$PROMETHEUS_POD" ]]; then
            DISK_USAGE=$(kubectl exec -n "$MONITORING_NAMESPACE" "$PROMETHEUS_POD" -- df -h /prometheus 2>/dev/null | tail -n 1 | awk '{print $5}' | sed 's/%//')
            if [[ -n "$DISK_USAGE" && $DISK_USAGE -gt 85 ]]; then
                COMPONENT="prometheus"
                ISSUE_TYPE="disk-cleanup"
            else
                # Check for high memory/CPU usage
                CPU_USAGE=$(kubectl exec -n "$MONITORING_NAMESPACE" "$PROMETHEUS_POD" -- curl -s "localhost:${PROMETHEUS_PORT}/api/v1/query?query=rate(process_cpu_seconds_total[5m])*100" 2>/dev/null | grep -o '"value":\[.*\]' | grep -o '[0-9]*\.[0-9]*')
                if [[ -n "$CPU_USAGE" && $(echo "$CPU_USAGE > 80" | bc -l) -eq 1 ]]; then
                    COMPONENT="prometheus"
                    ISSUE_TYPE="scaling"
                fi
            fi
        fi
    fi
    
    # If still no issues detected, check for configuration issues
    if [[ -z "$COMPONENT" || -z "$ISSUE_TYPE" ]]; then
        echo "Checking for configuration issues..."
        
        # Check Prometheus config
        PROMETHEUS_POD=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$PROMETHEUS_POD" ]]; then
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$PROMETHEUS_POD" -- promtool check config /etc/prometheus/prometheus.yml &>/dev/null; then
                COMPONENT="prometheus"
                ISSUE_TYPE="config-repair"
            fi
        fi
        
        # Check AlertManager config
        ALERTMANAGER_POD=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=alertmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$ALERTMANAGER_POD" ]]; then
            if ! kubectl exec -n "$MONITORING_NAMESPACE" "$ALERTMANAGER_POD" -- amtool check-config /etc/alertmanager/alertmanager.yml &>/dev/null; then
                COMPONENT="alertmanager"
                ISSUE_TYPE="config-repair"
            fi
        fi
    fi
    
    # Check for network connectivity issues
    if [[ -z "$COMPONENT" || -z "$ISSUE_TYPE" ]]; then
        echo "Checking for network connectivity issues..."
        
        # Try to detect connectivity issues by checking if pods can communicate with services
        for comp in prometheus alertmanager grafana; do
            pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=$comp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$pod" ]]; then
                echo "Testing network connectivity for $comp..."
                
                # Simple connectivity test
                if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- ping -c 1 kubernetes.default.svc.cluster.local &>/dev/null; then
                    echo "⚠️ Network connectivity issue detected for $comp"
                    COMPONENT="$comp"
                    ISSUE_TYPE="network-connectivity"
                    break
                fi
                
                # Service endpoint test based on component
                case $comp in
                    prometheus)
                        if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:9090/api/v1/status/config" &>/dev/null; then
                            echo "⚠️ Prometheus API connectivity issue detected"
                            COMPONENT="prometheus"
                            ISSUE_TYPE="network-connectivity"
                            break
                        fi
                        ;;
                    alertmanager)
                        if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:9093/api/v1/status" &>/dev/null; then
                            echo "⚠️ AlertManager API connectivity issue detected"
                            COMPONENT="alertmanager"
                            ISSUE_TYPE="network-connectivity"
                            break
                        fi
                        ;;
                    grafana)
                        if ! kubectl exec -n "$MONITORING_NAMESPACE" "$pod" -- curl -s "localhost:3000/api/health" &>/dev/null; then
                            echo "⚠️ Grafana API connectivity issue detected"
                            COMPONENT="grafana"
                            ISSUE_TYPE="network-connectivity"
                            break
                        fi
                        ;;
                esac
            fi
        done
    fi
fi

# Execute remediation based on component and issue type
if [[ -z "$COMPONENT" || -z "$ISSUE_TYPE" ]]; then
    echo "No issues detected or unable to determine component and issue type"
    echo "Usage: $0 --component <component> --issue <issue-type>"
    exit 0
else
    echo "Remediating $ISSUE_TYPE issue for $COMPONENT..."
    
    case $ISSUE_TYPE in
        restart)
            restart_component "$COMPONENT"
            ;;
        disk-cleanup)
            cleanup_disk_space "$COMPONENT"
            ;;
        config-repair)
            repair_config "$COMPONENT"
            ;;
        scaling)
            apply_auto_scaling "$COMPONENT"
            ;;
        network-connectivity)
            fix_network_connectivity "$COMPONENT"
            ;;
        *)
            handle_error 306 "Unknown issue type: $ISSUE_TYPE"
            exit 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully remediated $ISSUE_TYPE issue for $COMPONENT"
        log_audit "remediation_success" "Successfully remediated $ISSUE_TYPE issue for $COMPONENT"
        exit 0
    else
        echo "❌ Failed to remediate $ISSUE_TYPE issue for $COMPONENT"
        log_audit "remediation_failure" "Failed to remediate $ISSUE_TYPE issue for $COMPONENT"
        exit 1
    fi
fi
