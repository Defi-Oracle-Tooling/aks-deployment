#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/../deployment/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE=$(get_namespace "blockchain")

# Function to start a service
start_service() {
    local service=$1
    local replicas=${2:-1}
    echo "Starting $service..."
    kubectl scale deployment "$service" --replicas="$replicas" -n "$NAMESPACE"
}

# Function to stop a service
stop_service() {
    local service=$1
    echo "Stopping $service..."
    kubectl scale deployment "$service" --replicas=0 -n "$NAMESPACE"
}

# Function to restart a service
restart_service() {
    local service=$1
    local replicas=${2:-1}
    echo "Restarting $service..."
    stop_service "$service"
    sleep 5
    start_service "$service" "$replicas"
}

# Main execution
case "$1" in
    start)
        start_service "$2" "$3"
        ;;
    stop)
        stop_service "$2"
        ;;
    restart)
        restart_service "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart} <service-name> [replicas]"
        exit 1
        ;;
esac
