#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"

# Function to generate config file
generate_config() {
    local dir=$1
    local name=$2
    local content=$3
    
    mkdir -p "${CONFIG_ROOT}/${dir}"
    echo "$content" > "${CONFIG_ROOT}/${dir}/${name}.json"
}

# Generate namespace config
generate_config "common" "namespaces" '{
  "namespaces": {
    "blockchain": {
      "mainnet": "besu-mainnet",
      "testnet": "besu-testnet",
      "devnet": "besu-devnet",
      "default": "besu"
    },
    "monitoring": {
      "default": "monitoring",
      "metrics": "metrics",
      "alerts": "alerts"
    }
  }
}'

# Generate other configs with default values
generate_default_configs() {
    for provider in "azure" "aws" "gcp"; do
        for type in "regions" "networks" "storage"; do
            generate_config "cloud_providers/${provider}" "${provider}_${type}" '{
  "warning": "This is a generated default config. Please update with actual values.",
  "generated": true,
  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
}'
        done
    done
}

generate_default_configs
