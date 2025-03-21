#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
SECURITY_CHECK_TIMEOUT=300 # 5 minutes

verify_network_policies() {
    local region=$1
    
    echo "Verifying network policies in $region..."
    
    # Verify default deny policy
    local deny_policy=$(kubectl get networkpolicy -n besu default-deny-all -o json)
    if [[ -z "$deny_policy" ]]; then
        handle_error 80 "Default deny network policy not found in ${region}"
        return 1
    fi
    
    # Verify Besu network policies
    local besu_policies=$(kubectl get networkpolicy -n besu -l app.kubernetes.io/part-of=besu-network -o json)
    if [[ -z "$besu_policies" ]]; then
        handle_error 81 "Besu network policies not found in ${region}"
        return 1
    fi
    
    return 0
}

verify_pod_security_policies() {
    local region=$1
    
    echo "Verifying pod security policies in $region..."
    
    # Check if PSP is enabled and configured
    local psp_status=$(kubectl get psp besu-restricted -o json)
    if [[ -z "$psp_status" ]]; then
        handle_error 82 "Pod Security Policy not found in ${region}"
        return 1
    fi
    
    return 0
}

verify_audit_policies() {
    local region=$1
    
    echo "Verifying audit policies in $region..."
    
    # Check audit policy configuration
    local audit_policy=$(kubectl get --raw "/apis/audit.k8s.io/v1/policies")
    if ! echo "$audit_policy" | grep -q "besu-audit-policy"; then
        handle_error 83 "Audit policy not found in ${region}"
        return 1
    fi
    
    return 0
}

verify_azure_key_vault() {
    local region=$1
    
    echo "Verifying Azure Key Vault integration in $region..."
    
    # Check Key Vault identity binding
    local identity_binding=$(kubectl get AzureIdentityBinding -n besu -l app.kubernetes.io/part-of=besu-network -o json)
    if [[ -z "$identity_binding" ]]; then
        handle_error 84 "Azure Identity Binding not found in ${region}"
        return 1
    fi
    
    return 0
}

verify_security_context() {
    local region=$1
    
    echo "Verifying security contexts in $region..."
    
    # Check pod security contexts
    local pods_context=$(kubectl get pods -n besu -o json | \
        jq -r '.items[] | select(.spec.securityContext.runAsNonRoot != true) | .metadata.name')
    
    if [[ ! -z "$pods_context" ]]; then
        handle_error 85 "Pods without proper security context found in ${region}: ${pods_context}"
        return 1
    fi
    
    return 0
}

verify_all_security() {
    local region=$1
    local start_time=$(date +%s)
    
    echo "Starting security verification for $region..."
    
    # Run all security verifications
    verify_network_policies "$region" && \
    verify_pod_security_policies "$region" && \
    verify_audit_policies "$region" && \
    verify_azure_key_vault "$region" && \
    verify_security_context "$region"
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        echo "✅ Security verification successful for $region"
        log_audit "security_verification" "All security checks passed for ${region}"
    else
        echo "❌ Security verification failed for $region"
    fi
    
    return $result
}

# Main verification process
echo "Starting security verification process..."

failed_regions=()

while read -r region; do
    if ! verify_all_security "$region"; then
        failed_regions+=("$region")
    fi
done < regions.txt

# Final verification status
if [[ ${#failed_regions[@]} -gt 0 ]]; then
    echo "❌ Security verification failed in regions: ${failed_regions[*]}"
    exit 1
else
    echo "✅ Security verification completed successfully in all regions!"
    exit 0
fi