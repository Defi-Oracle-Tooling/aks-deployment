#!/bin/bash

# Constants
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"
CONFIG_FILE="${CONFIG_ROOT}/dynamic_config.json"

# Function to load config values
get_config() {
    local key=$1
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found at $CONFIG_FILE" >&2
        return 1
    fi
    jq -r "$key" "$CONFIG_FILE"
}

# Function to set config values
set_config() {
    local key=$1
    local value=$2
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "{}" > "$CONFIG_FILE"
    fi
    local temp_file=$(mktemp)
    jq "$key = $value" "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# Function to validate config structure
validate_config() {
    local config_file=$1
    if ! jq empty "$config_file" 2>/dev/null; then
        echo "Error: Invalid JSON in $config_file" >&2
        return 1
    fi
    return 0
}
