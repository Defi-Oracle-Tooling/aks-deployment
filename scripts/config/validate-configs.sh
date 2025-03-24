#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
SCHEMA_DIR="${PROJECT_ROOT}/config/schemas"
CONFIG_ROOT="${PROJECT_ROOT}/config"

# Check if jsonschema is installed
if ! command -v jsonschema &> /dev/null; then
    echo "Installing jsonschema..."
    pip install jsonschema
fi

# Validate config against schema
validate_config() {
    local config_file=$1
    local schema_file=$2
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Config file not found: $config_file"
        return 1
    fi
    
    if [[ ! -f "$schema_file" ]]; then
        echo "❌ Schema file not found: $schema_file"
        return 1
    }
    
    if jsonschema -i "$config_file" "$schema_file"; then
        echo "✅ Valid: $config_file"
        return 0
    else
        echo "❌ Invalid: $config_file"
        return 1
    fi
}

# Validate all configs
find "$CONFIG_ROOT" -type f -name "*.json" | while read -r config; do
    name=$(basename "$config" .json)
    schema="${SCHEMA_DIR}/${name}-schema.json"
    validate_config "$config" "$schema"
done
