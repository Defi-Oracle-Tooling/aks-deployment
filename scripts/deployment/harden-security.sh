#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"

harden_aks_cluster() {
    local region=$1
    
    echo "Hardening AKS cluster in $region..."
    
    # Enable Azure Policy for AKS
    az aks update \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --enable-azure-policy \
        --api-server-authorized-ip-ranges "$(curl -s ifconfig.me)/32"
    
    # Enable node image auto-upgrade
    az aks update \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --enable-node-image-upgrade
        
    log_audit "cluster_hardened" "AKS cluster hardening completed in ${region}"
}

configure_network_security() {
    echo "Configuring network security policies..."
    
    # Apply network policies
    kubectl apply -f ../infrastructure/kubernetes/security-policies.yaml
    
    # Verify network policies
    if ! kubectl get networkpolicies -n "$NAMESPACE" | grep -q "default-deny-all"; then
        handle_error 70 "Failed to apply network policies"
        return 1
    fi
    
    log_audit "network_security_configured" "Network security policies applied"
}

configure_pod_security() {
    echo "Configuring pod security policies..."
    
    # Enable pod security policy admission controller if not enabled
    if ! kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' | grep -q "PodSecurityPolicy"; then
        handle_error 71 "Pod security policy admission controller not enabled"
        return 1
    fi
    
    # Apply pod security policies
    kubectl apply -f ../infrastructure/kubernetes/security-policies.yaml
    
    log_audit "pod_security_configured" "Pod security policies applied"
}

configure_rbac() {
    echo "Configuring RBAC policies..."
    
    # Create service accounts if they don't exist
    for sa in validator bootnode rpc; do
        if ! kubectl get serviceaccount "besu-${sa}" -n "$NAMESPACE" 2>/dev/null; then
            kubectl create serviceaccount "besu-${sa}" -n "$NAMESPACE"
        fi
    done
    
    # Apply RBAC roles and bindings
    kubectl apply -f ../infrastructure/kubernetes/security-policies.yaml
    
    log_audit "rbac_configured" "RBAC policies applied"
}

configure_secrets_encryption() {
    echo "Configuring secrets encryption..."
    
    # Enable encryption at rest for secrets
    az aks update \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --enable-encryption-at-host
        
    log_audit "secrets_encryption_configured" "Secrets encryption enabled"
}

configure_monitoring_security() {
    echo "Configuring monitoring security..."
    
    # Apply monitoring namespace network policies
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-ingress
  namespace: $MONITORING_NAMESPACE
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: besu
EOF
    
    log_audit "monitoring_security_configured" "Monitoring security policies applied"
}

verify_security_configuration() {
    echo "Verifying security configuration..."
    
    # Verify network policies
    if ! kubectl get networkpolicies -n "$NAMESPACE" | grep -q "default-deny-all"; then
        handle_error 72 "Network policies verification failed"
        return 1
    fi
    
    # Verify pod security policies
    if ! kubectl get psp besu-restricted; then
        handle_error 73 "Pod security policies verification failed"
        return 1
    fi
    
    # Verify RBAC configuration
    if ! kubectl get role psp:besu-restricted -n "$NAMESPACE"; then
        handle_error 74 "RBAC configuration verification failed"
        return 1
    fi
    
    log_audit "security_verified" "Security configuration verified"
}

# Main hardening process
echo "Starting security hardening process..."

while read -r region; do
    echo "Hardening deployment in $region..."
    
    # Get AKS credentials
    if ! az aks get-credentials \
        --resource-group "${RESOURCE_GROUP_PREFIX}-${region}" \
        --name "${AKS_CLUSTER_PREFIX}-${region}" \
        --overwrite-existing; then
        handle_error 75 "Failed to get AKS credentials for ${region}"
        continue
    fi
    
    # Run hardening steps
    harden_aks_cluster "$region" && \
    configure_network_security && \
    configure_pod_security && \
    configure_rbac && \
    configure_secrets_encryption && \
    configure_monitoring_security && \
    verify_security_configuration
    
    if [ $? -eq 0 ]; then
        echo "✅ Security hardening successful for $region"
        log_audit "hardening_success" "Security hardening completed for ${region}"
    else
        echo "❌ Security hardening failed for $region"
        echo "$region" >> "$FAILED_REGIONS_LOG"
        handle_error 76 "Security hardening failed for ${region}"
    fi
done < regions.txt

# Final status check
if [ -s "$FAILED_REGIONS_LOG" ]; then
    echo "❌ Security hardening failed in some regions. Check $FAILED_REGIONS_LOG for details."
    exit 1
else
    echo "✅ Security hardening completed successfully in all regions!"
    exit 0
fi