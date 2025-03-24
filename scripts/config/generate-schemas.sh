#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
SCHEMA_DIR="${PROJECT_ROOT}/config/schemas"

mkdir -p "$SCHEMA_DIR"

# Generate namespace schema
cat > "${SCHEMA_DIR}/namespaces-schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["namespaces"],
  "properties": {
    "namespaces": {
      "type": "object",
      "required": ["blockchain", "monitoring", "testing", "infrastructure"],
      "properties": {
        "blockchain": {
          "type": "object",
          "required": ["default"],
          "properties": {
            "mainnet": { "type": "string" },
            "testnet": { "type": "string" },
            "devnet": { "type": "string" },
            "default": { "type": "string" }
          }
        },
        "monitoring": {
          "type": "object",
          "required": ["default"],
          "properties": {
            "default": { "type": "string" },
            "metrics": { "type": "string" },
            "alerts": { "type": "string" }
          }
        }
      }
    }
  }
}
EOF

# Generate other schemas
generate_schema() {
    local name=$1
    local schema_file="${SCHEMA_DIR}/${name}-schema.json"
    shift
    local properties=("$@")
    
    local props_json=""
    for prop in "${properties[@]}"; do
        props_json+='"'$prop'": {"type": "string"},'
    done
    props_json=${props_json%,}
    
    cat > "$schema_file" << EOF
{
  "\$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": [$(printf '"%s",' "${properties[@]}" | sed 's/,$//')],
  "properties": {
    $props_json
  }
}
EOF
}

# Generate schemas for each config type
generate_schema "regions" "name" "location" "enabled"
generate_schema "vm-families" "family" "size" "vcpus" "memory"
generate_schema "networks" "vnet" "subnet" "security_group"
