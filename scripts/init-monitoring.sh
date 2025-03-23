#!/bin/bash

# Source deployment utilities
source "$(dirname "$0")/deployment/deployment-utils.sh"

# Initialize logging
setup_logging

# Constants
HELM_TIMEOUT="5m"

# Get namespace from configuration
NAMESPACE=$(get_namespace "monitoring")

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus Stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --set prometheus.prometheusSpec.retention=15d \
    --set prometheus.prometheusSpec.retentionSize="45GB" \
    --timeout "$HELM_TIMEOUT" \
    --wait

# Install Grafana dashboards
kubectl apply -f "${PROJECT_ROOT}/monitoring/grafana/dashboards/" -n "$NAMESPACE"

# Configure ServiceMonitors
kubectl apply -f "${PROJECT_ROOT}/monitoring/prometheus/service-monitors/" -n "$NAMESPACE"

echo "✅ Monitoring stack initialized successfully"
log_audit "monitoring_initialized" "Monitoring stack deployment completed"
