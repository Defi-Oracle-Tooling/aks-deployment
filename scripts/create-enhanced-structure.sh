#!/bin/bash

# Create directory structure for enhanced components
mkdir -p "${PROJECT_ROOT}"/{"frontend/web3","middleware/api","backend/db","ai/agents","ai/orchestration"}

# Create subdirectories
cd "${PROJECT_ROOT}"
mkdir -p frontend/web3/{components,contracts,hooks,styles}
mkdir -p middleware/api/{routes,services,validators}
mkdir -p backend/db/{migrations,models,schemas}
mkdir -p ai/{agents,orchestration,models,training}
