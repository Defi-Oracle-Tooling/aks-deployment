#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
CONFIG_ROOT="${PROJECT_ROOT}/config"

# Function to check JSON syntax
check_json() {
    local file=$1
    if jq empty "$file" 2>/dev/null; then
        echo "✅ Valid JSON: $file"
        return 0
    else
        echo "❌ Invalid JSON: $file"
        return 1
    fi
}

# Function to check required fields
check_required_fields() {
    local file=$1
    local type=$(basename "$file" .json)
    
    case $type in
        *regions*)
            jq -e '.regions' "$file" >/dev/null 2>&1 || 
                { echo "❌ Missing required field 'regions' in $file"; return 1; }
            ;;
        *networks*)
            jq -e '.networks' "$file" >/dev/null 2>&1 || 
                { echo "❌ Missing required field 'networks' in $file"; return 1; }
            ;;
        *namespaces*)
            jq -e '.namespaces' "$file" >/dev/null 2>&1 || 
                { echo "❌ Missing required field 'namespaces' in $file"; return 1; }
            ;;
    esac
    return 0
}

# Check all JSON files
find "$CONFIG_ROOT" -type f -name "*.json" | while read -r file; do
    echo "Checking $file..."
    if check_json "$file"; then
        check_required_fields "$file"
    fi
done
