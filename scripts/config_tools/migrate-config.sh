#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"
MIGRATIONS_DIR="${PROJECT_ROOT}/scripts/config_tools/migrations"

# Migration functions
migrate_config() {
    local src_env=$1
    local dst_env=$2
    local config_type=$3
    
    # Validate environments
    if [[ ! -d "${CONFIG_ROOT}/${src_env}" ]]; then
        echo "Source environment not found: $src_env"
        exit 1
    fi
    
    # Create destination directory
    mkdir -p "${CONFIG_ROOT}/${dst_env}"
    
    # Copy and transform configs
    find "${CONFIG_ROOT}/${src_env}" -name "*.json" | while read -r src_file; do
        local dst_file="${CONFIG_ROOT}/${dst_env}/$(basename "$src_file")"
        transform_config "$src_file" "$dst_file" "$dst_env"
    done
}

transform_config() {
    local src_file=$1
    local dst_file=$2
    local env=$3
    
    # Apply environment-specific transformations
    case $env in
        production)
            jq '.debug = false | .logging.level = "info"' "$src_file" > "$dst_file"
            ;;
        staging)
            jq '.debug = true | .logging.level = "debug"' "$src_file" > "$dst_file"
            ;;
        development)
            jq '.debug = true | .logging.level = "debug"' "$src_file" > "$dst_file"
            ;;
    esac
}

main() {
    local src_env=${1:-"development"}
    local dst_env=${2:-"production"}
    local config_type=${3:-"all"}
    
    migrate_config "$src_env" "$dst_env" "$config_type"
}

main "$@"
