#!/bin/bash

# Set project root
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

# Source deployment utilities
source "${PROJECT_ROOT}/scripts/deployment/deployment-utils.sh"

# Parse command line arguments
usage() {
    echo "Usage: $0 [--network <mainnet|testnet|devnet>] [--region <region-name>]"
    echo "Default network: mainnet"
    exit 1
}

NETWORK="mainnet"
REGION=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --network)
            NETWORK="$2"
            shift
            shift
            ;;
        --region)
            REGION="$2"
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

# Load network-specific security configurations
case $NETWORK in
    "mainnet")
        CHAIN_ID=138
        POD_SECURITY_LEVEL="restricted"
        ALLOW_PRIVILEGED="false"
        REQUIRE_HTTPS="true"
        ENCRYPTION_AT_REST="true"
        MIN_TLS_VERSION="1.3"
        NETWORK_POLICY_ENFORCEMENT="true"
        AZURE_POLICY="true"
        ;;
    "testnet")
        CHAIN_ID=2138
        POD_SECURITY_LEVEL="baseline"
        ALLOW_PRIVILEGED="false"
        REQUIRE_HTTPS="true"
        ENCRYPTION_AT_REST="true"
        MIN_TLS_VERSION="1.2"
        NETWORK_POLICY_ENFORCEMENT="true"
        AZURE_POLICY="true"
        ;;
    "devnet")
        CHAIN_ID=1337
        POD_SECURITY_LEVEL="privileged"
        ALLOW_PRIVILEGED="true"
        REQUIRE_HTTPS="false"
        ENCRYPTION_AT_REST="false"
        MIN_TLS_VERSION="1.2"
        NETWORK_POLICY_ENFORCEMENT="false"
        AZURE_POLICY="false"
        ;;
    *)
        echo "Error: Invalid network type"
        exit 1
        ;;
esac

# Function to configure AKS security settings
configure_aks_security() {
    local region=$1
    echo "Configuring AKS security settings for $NETWORK in $region..."

    # Update AKS cluster security settings
    az aks update \
        --resource-group "besu-network-${region}" \
        --name "besu-aks-${region}" \
        --api-server-authorized-ip-ranges "0.0.0.0/0" \
        --enable-pod-security-policy \
        --network-policy "azure" \
        --enable-encryption-at-host $ENCRYPTION_AT_REST \
        --enable-azure-policy $AZURE_POLICY \
        --min-tls-version $MIN_TLS_VERSION

    # Apply pod security policies
    kubectl apply -f - <<EOF
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: besu-${NETWORK}-psp
spec:
  privileged: ${ALLOW_PRIVILEGED}
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: MustRunAs
    ranges:
      - min: 1
        max: 65535
  runAsUser:
    rule: MustRunAsNonRoot
  fsGroup:
    rule: MustRunAs
    ranges:
      - min: 1
        max: 65535
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
EOF

    # Apply network policies based on network type
    apply_network_policies "$region"
}

# Function to apply network policies
apply_network_policies() {
    local region=$1
    echo "Applying network policies for $NETWORK in $region..."

    if [ "$NETWORK_POLICY_ENFORCEMENT" = "true" ]; then
        kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: besu-${NETWORK}-policy
  namespace: besu
spec:
  podSelector:
    matchLabels:
      network.besu.hyperledger.org/chainId: "${CHAIN_ID}"
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          network.besu.hyperledger.org/chainId: "${CHAIN_ID}"
    ports:
    - protocol: TCP
      port: 30303
    - protocol: UDP
      port: 30303
    - protocol: TCP
      port: 8545
  egress:
  - to:
    - podSelector:
        matchLabels:
          network.besu.hyperledger.org/chainId: "${CHAIN_ID}"
EOF
    fi
}

# Function to configure Azure Key Vault integration
configure_key_vault() {
    local region=$1
    echo "Configuring Azure Key Vault for $NETWORK in $region..."

    # Create Key Vault if it doesn't exist
    az keyvault create \
        --resource-group "besu-network-${region}" \
        --name "besu-${NETWORK}-${region}-kv" \
        --sku "Premium" \
        --enabled-for-deployment true \
        --enabled-for-disk-encryption true \
        --enabled-for-template-deployment true

    # Enable Key Vault encryption if required
    if [ "$ENCRYPTION_AT_REST" = "true" ]; then
        az keyvault update \
            --resource-group "besu-network-${region}" \
            --name "besu-${NETWORK}-${region}-kv" \
            --enable-soft-delete true \
            --enable-purge-protection true
    fi
}

# Function to configure HTTPS requirements
configure_https() {
    local region=$1
    echo "Configuring HTTPS requirements for $NETWORK in $region..."

    if [ "$REQUIRE_HTTPS" = "true" ]; then
        # Install cert-manager
        kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.7.0/cert-manager.yaml

        # Create ClusterIssuer for Let's Encrypt
        kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-${NETWORK}
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourcompany.com
    privateKeySecretRef:
      name: letsencrypt-${NETWORK}
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    fi
}

# Function to apply security monitoring
configure_security_monitoring() {
    local region=$1
    echo "Configuring security monitoring for $NETWORK in $region..."

    # Enable Azure Security Center
    az security pricing create -n KubernetesService --tier "Standard"

    # Configure Azure Monitor for containers
    az monitor log-analytics workspace create \
        --resource-group "besu-network-${region}" \
        --workspace-name "besu-${NETWORK}-${region}-logs" \
        --location "$region"

    # Enable container insights
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "besu-network-${region}" \
        --workspace-name "besu-${NETWORK}-${region}-logs" \
        --query "id" -o tsv)

    az aks enable-addons \
        --resource-group "besu-network-${region}" \
        --name "besu-aks-${region}" \
        --addons monitoring \
        --workspace-resource-id "$WORKSPACE_ID"
}

# Main security hardening process
if [ -n "$REGION" ]; then
    # Configure security for single region
    echo "🔒 Starting security hardening for $NETWORK in $REGION..."
    configure_aks_security "$REGION" && \
    configure_key_vault "$REGION" && \
    configure_https "$REGION" && \
    configure_security_monitoring "$REGION"
else
    # Configure security for all regions
    echo "🔒 Starting security hardening for $NETWORK in all regions..."
    for region in $(az aks list --query "[].location" -o tsv | sort -u); do
        echo "Configuring security in region: $region"
        configure_aks_security "$region" && \
        configure_key_vault "$region" && \
        configure_https "$region" && \
        configure_security_monitoring "$region" || \
        echo "❌ Security configuration failed in $region"
    done
fi