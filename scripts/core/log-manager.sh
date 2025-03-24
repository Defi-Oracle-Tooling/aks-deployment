#!/bin/bash

# Constants
LOG_DIR="/var/log/besu"
DEPLOYMENT_LOG="${LOG_DIR}/deployment.log"
ERROR_LOG="${LOG_DIR}/error.log"
AUDIT_LOG="${LOG_DIR}/audit.log"

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}"
    for log_file in "$DEPLOYMENT_LOG" "$ERROR_LOG" "$AUDIT_LOG"; do
        touch "$log_file"
        chmod 644 "$log_file"
    done
}

# Log message with timestamp
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"${timestamp}\",\"level\":\"${level}\",\"message\":\"${message}\"}" >> "$DEPLOYMENT_LOG"
}

# Log error with code
log_error() {
    local code=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"${timestamp}\",\"code\":${code},\"message\":\"${message}\"}" >> "$ERROR_LOG"
}

# Log audit event
log_audit() {
    local action=$1
    local details=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local user=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
    echo "{\"timestamp\":\"${timestamp}\",\"user\":\"${user}\",\"action\":\"${action}\",\"details\":\"${details}\"}" >> "$AUDIT_LOG"
}
