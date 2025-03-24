#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"
TEMPLATE_DIR="${PROJECT_ROOT}/scripts/config_tools/templates"

# Function to initialize config files
init_config() {
    local config_type=$1
    local env=${2:-"development"}
    
    case $config_type in
        namespaces)
            init_namespace_config "$env"
            ;;
        cloud)
            init_cloud_config "$env"
            ;;
        monitoring)
            init_monitoring_config "$env"
            ;;
        all)
            init_namespace_config "$env"
            init_cloud_config "$env"
            init_monitoring_config "$env"
            ;;
        *)
            echo "Unknown config type: $config_type"
            exit 1
            ;;
    esac
}

# Initialize with user input
init_namespace_config() {
    local env=$1
    local output_file="${CONFIG_ROOT}/common/namespaces_${env}.json"
    
    read -p "Enter blockchain namespace prefix [besu]: " blockchain_prefix
    blockchain_prefix=${blockchain_prefix:-besu}
    
    read -p "Enter monitoring namespace [monitoring]: " monitoring_ns
    monitoring_ns=${monitoring_ns:-monitoring}
    
    cat > "$output_file" << EOF
{
    "namespaces": {
        "blockchain": {
            "mainnet": "${blockchain_prefix}-mainnet",
            "testnet": "${blockchain_prefix}-testnet",
            "devnet": "${blockchain_prefix}-devnet",
            "default": "${blockchain_prefix}"
        },
        "monitoring": {
            "default": "${monitoring_ns}"
        }
    }
}
EOF
}

main() {
    local config_type=${1:-"all"}
    local env=${2:-"development"}
    
    init_config "$config_type" "$env"
}

main "$@"
