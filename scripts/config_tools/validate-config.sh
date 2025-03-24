#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"
SCHEMA_DIR="${PROJECT_ROOT}/config/schemas"

# Validation functions
validate_json() {
    local file=$1
    if ! jq empty "$file" 2>/dev/null; then
        echo "❌ Invalid JSON: $file"
        return 1
    fi
    return 0
}

validate_namespaces() {
    local file=$1
    local required_namespaces=("blockchain" "monitoring")
    
    for ns in "${required_namespaces[@]}"; do
        if ! jq -e ".namespaces.$ns" "$file" >/dev/null 2>&1; then
            echo "❌ Missing required namespace: $ns in $file"
            return 1
        fi
    done
    return 0
}

validate_references() {
    local file=$1
    local refs=($(jq -r '.. | .reference? | select(.)' "$file"))
    
    for ref in "${refs[@]}"; do
        local ref_file="${CONFIG_ROOT}/${ref}"
        if [[ ! -f "$ref_file" ]]; then
            echo "❌ Referenced file not found: $ref_file"
            return 1
        fi
    done
    return 0
}

main() {
    local config_type=${1:-"all"}
    local env=${2:-"development"}
    
    find "$CONFIG_ROOT" -type f -name "*.json" | while read -r file; do
        echo "Validating: $file"
        validate_json "$file" || continue
        validate_namespaces "$file" || continue
        validate_references "$file" || continue
        echo "✅ Validation passed: $file"
    done
}

main "$@"
