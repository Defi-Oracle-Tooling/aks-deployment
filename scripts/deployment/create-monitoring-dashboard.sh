#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"
GRAFANA_PORT=3000
GRAFANA_API_KEY="${GRAFANA_API_KEY:-admin:admin}"  # Default credentials, should be overridden in production
DASHBOARD_TITLE="Enhanced Monitoring Dashboard"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --multi-cluster)
            MULTI_CLUSTER=true
            shift
            ;;
        --alert-view)
            ALERT_VIEW=true
            shift
            ;;
        --trends)
            TRENDS=true
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift
            shift
            ;;
        --monitoring-namespace)
            MONITORING_NAMESPACE="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--multi-cluster] [--alert-view] [--trends] [--namespace <namespace>] [--monitoring-namespace <monitoring-namespace>]"
            exit 1
            ;;
    esac
done

echo "Creating enhanced monitoring dashboard..."

# Get Grafana pod
grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$grafana_pod" ]]; then
    handle_error 200 "Grafana pod not found"
    exit 1
fi

# Function to create the base dashboard JSON structure
create_base_dashboard() {
    cat > /tmp/enhanced_dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Enhanced Monitoring Dashboard",
    "tags": ["besu", "monitoring", "enhanced"],
    "timezone": "browser",
    "schemaVersion": 21,
    "version": 1,
    "refresh": "10s",
    "panels": [],
    "templating": {
      "list": [
        {
          "allValue": null,
          "current": {
            "text": "All",
            "value": "$__all"
          },
          "datasource": "Prometheus",
          "definition": "label_values(kube_namespace_labels, namespace)",
          "hide": 0,
          "includeAll": true,
          "label": "Namespace",
          "multi": false,
          "name": "namespace",
          "options": [],
          "query": "label_values(kube_namespace_labels, namespace)",
          "refresh": 1,
          "regex": "",
          "skipUrlSync": false,
          "sort": 0,
          "tagValuesQuery": "",
          "tags": [],
          "tagsQuery": "",
          "type": "query",
          "useTags": false
        },
        {
          "allValue": null,
          "current": {
            "text": "All",
            "value": "$__all"
          },
          "datasource": "Prometheus",
          "definition": "label_values(kube_node_info, node)",
          "hide": 0,
          "includeAll": true,
          "label": "Node",
          "multi": true,
          "name": "node",
          "options": [],
          "query": "label_values(kube_node_info, node)",
          "refresh": 1,
          "regex": "",
          "skipUrlSync": false,
          "sort": 0,
          "tagValuesQuery": "",
          "tags": [],
          "tagsQuery": "",
          "type": "query",
          "useTags": false
        }
      ]
    },
    "time": {
      "from": "now-6h",
      "to": "now"
    },
    "timepicker": {
      "refresh_intervals": [
        "5s",
        "10s",
        "30s",
        "1m",
        "5m",
        "15m",
        "30m",
        "1h",
        "2h",
        "1d"
      ],
      "time_options": [
        "5m",
        "15m",
        "1h",
        "6h",
        "12h",
        "24h",
        "2d",
        "7d",
        "30d"
      ]
    },
    "links": []
  },
  "overwrite": true,
  "inputs": [],
  "folderId": 0
}
EOF
}

# Function to add real-time cluster health metrics
add_cluster_health_metrics() {
    local dashboard_json=$1
    
    # Create a panel for cluster health metrics
    cat > /tmp/cluster_health.json << 'EOF'
[
  {
    "title": "Cluster Overview",
    "type": "stat",
    "datasource": "Prometheus",
    "gridPos": { "h": 4, "w": 24, "x": 0, "y": 0 },
    "id": 1,
    "options": {
      "colorMode": "value",
      "graphMode": "none",
      "justifyMode": "auto",
      "orientation": "horizontal",
      "reduceOptions": {
        "calcs": ["mean"],
        "fields": "",
        "values": false
      }
    },
    "pluginVersion": "7.3.0",
    "targets": [
      {
        "expr": "count(kube_node_info)",
        "instant": true,
        "legendFormat": "Nodes",
        "refId": "A"
      },
      {
        "expr": "count(kube_pod_info{namespace=~\"$namespace\"})",
        "instant": true,
        "legendFormat": "Pods",
        "refId": "B"
      },
      {
        "expr": "count(kube_pod_container_status_ready{namespace=~\"$namespace\"} == 1) / count(kube_pod_info{namespace=~\"$namespace\"}) * 100",
        "instant": true,
        "legendFormat": "Pod Readiness (%)",
        "refId": "C"
      },
      {
        "expr": "count(kube_pod_container_status_running{namespace=~\"$namespace\"} == 1)",
        "instant": true,
        "legendFormat": "Running Containers",
        "refId": "D"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "mappings": [],
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        },
        "unit": "none"
      },
      "overrides": [
        {
          "matcher": {
            "id": "byName",
            "options": "Pod Readiness (%)"
          },
          "properties": [
            {
              "id": "unit",
              "value": "percent"
            }
          ]
        }
      ]
    }
  },
  {
    "title": "Node Resources",
    "type": "gauge",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
    "id": 2,
    "options": {
      "orientation": "auto",
      "reduceOptions": {
        "calcs": ["mean"],
        "fields": "",
        "values": false
      },
      "showThresholdLabels": false,
      "showThresholdMarkers": true
    },
    "targets": [
      {
        "expr": "sum(node_memory_MemTotal_bytes{node=~\"$node\"} - node_memory_MemAvailable_bytes{node=~\"$node\"}) / sum(node_memory_MemTotal_bytes{node=~\"$node\"}) * 100",
        "legendFormat": "Memory Usage",
        "refId": "A"
      },
      {
        "expr": "sum(rate(node_cpu_seconds_total{mode!=\"idle\",node=~\"$node\"}[$__rate_interval])) / count(count by (cpu, node) (node_cpu_seconds_total{mode!=\"idle\",node=~\"$node\"})) * 100",
        "legendFormat": "CPU Usage",
        "refId": "B"
      },
      {
        "expr": "sum(node_filesystem_size_bytes{mountpoint=\"/\",node=~\"$node\"} - node_filesystem_free_bytes{mountpoint=\"/\",node=~\"$node\"}) / sum(node_filesystem_size_bytes{mountpoint=\"/\",node=~\"$node\"}) * 100",
        "legendFormat": "Disk Usage",
        "refId": "C"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "mappings": [],
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            },
            {
              "color": "yellow",
              "value": 70
            },
            {
              "color": "red",
              "value": 85
            }
          ]
        },
        "unit": "percent",
        "min": 0,
        "max": 100
      }
    }
  },
  {
    "title": "Pod Status",
    "type": "piechart",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
    "id": 3,
    "options": {
      "legend": {
        "show": true,
        "values": true
      },
      "pieType": "donut"
    },
    "targets": [
      {
        "expr": "sum(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Running\"}) or vector(0)",
        "legendFormat": "Running",
        "refId": "A"
      },
      {
        "expr": "sum(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Pending\"}) or vector(0)",
        "legendFormat": "Pending",
        "refId": "B"
      },
      {
        "expr": "sum(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Failed\"}) or vector(0)",
        "legendFormat": "Failed",
        "refId": "C"
      },
      {
        "expr": "sum(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Succeeded\"}) or vector(0)",
        "legendFormat": "Succeeded",
        "refId": "D"
      },
      {
        "expr": "sum(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Unknown\"}) or vector(0)",
        "legendFormat": "Unknown",
        "refId": "E"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "mappings": [],
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        },
        "color": {
          "mode": "palette-classic"
        }
      },
      "overrides": [
        {
          "matcher": {
            "id": "byName",
            "options": "Running"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "green",
                "mode": "fixed"
              }
            }
          ]
        },
        {
          "matcher": {
            "id": "byName",
            "options": "Pending"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "yellow",
                "mode": "fixed"
              }
            }
          ]
        },
        {
          "matcher": {
            "id": "byName",
            "options": "Failed"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "red",
                "mode": "fixed"
              }
            }
          ]
        }
      ]
    }
  },
  {
    "title": "Besu Metrics",
    "type": "table",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 24, "x": 0, "y": 12 },
    "id": 4,
    "options": {
      "showHeader": true
    },
    "targets": [
      {
        "expr": "besu_blockchain_height or besu_synchronizer_chain_head_block_number",
        "instant": true,
        "format": "table",
        "refId": "A"
      }
    ],
    "transformations": [
      {
        "id": "organize",
        "options": {
          "excludeByName": {
            "Time": true,
            "__name__": true,
            "container": true,
            "endpoint": true,
            "instance": true,
            "job": true
          },
          "indexByName": {},
          "renameByName": {
            "Value": "Block Height",
            "pod": "Pod",
            "namespace": "Namespace"
          }
        }
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {
          "align": "center",
          "displayMode": "auto",
          "filterable": true
        }
      }
    }
  },
  {
    "title": "Network Traffic",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 24, "x": 0, "y": 20 },
    "id": 5,
    "options": {
      "legend": {
        "show": true
      }
    },
    "targets": [
      {
        "expr": "sum(rate(container_network_receive_bytes_total{namespace=~\"$namespace\"}[$__rate_interval])) by (namespace)",
        "legendFormat": "In - {{namespace}}",
        "refId": "A"
      },
      {
        "expr": "sum(rate(container_network_transmit_bytes_total{namespace=~\"$namespace\"}[$__rate_interval])) by (namespace)",
        "legendFormat": "Out - {{namespace}}",
        "refId": "B"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "Bps",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  }
]
EOF
    
    # Add the panels to the dashboard
    jq --argjson panels "$(cat /tmp/cluster_health.json)" '.dashboard.panels = $panels' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
}

# Function to add multi-cluster view
add_multi_cluster_view() {
    local dashboard_json=$1
    
    # First, add cluster variable
    jq '(.dashboard.templating.list) += [{
      "allValue": null,
      "current": {
        "text": "All",
        "value": "$__all"
      },
      "hide": 0,
      "includeAll": true,
      "label": "Cluster",
      "multi": true,
      "name": "cluster",
      "options": [],
      "query": "label_values(kube_node_info, cluster)",
      "refresh": 1,
      "regex": "",
      "skipUrlSync": false,
      "sort": 0,
      "type": "query",
      "datasource": "Prometheus"
    }]' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
    
    # Create multi-cluster panels
    cat > /tmp/multi_cluster_panels.json << 'EOF'
[
  {
    "title": "Multi-Cluster Overview",
    "type": "stat",
    "datasource": "Prometheus",
    "gridPos": { "h": 4, "w": 24, "x": 0, "y": 28 },
    "id": 6,
    "options": {
      "colorMode": "value",
      "graphMode": "none",
      "justifyMode": "auto",
      "orientation": "horizontal",
      "reduceOptions": {
        "calcs": ["mean"],
        "fields": "",
        "values": false
      }
    },
    "targets": [
      {
        "expr": "count(kube_node_info) by (cluster)",
        "instant": true,
        "legendFormat": "Nodes in {{cluster}}",
        "refId": "A"
      },
      {
        "expr": "sum(kube_pod_info) by (cluster)",
        "instant": true,
        "legendFormat": "Pods in {{cluster}}",
        "refId": "B"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "mappings": [],
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        },
        "unit": "none"
      }
    }
  },
  {
    "title": "Cross-Cluster Network Latency",
    "type": "heatmap",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 0, "y": 32 },
    "id": 7,
    "targets": [
      {
        "expr": "avg(besu_network_peer_latency_seconds) by (cluster)",
        "legendFormat": "{{cluster}}",
        "refId": "A"
      }
    ],
    "options": {
      "yAxis": {
        "format": "ms"
      }
    }
  },
  {
    "title": "Cross-Cluster Block Heights",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 12, "y": 32 },
    "id": 8,
    "targets": [
      {
        "expr": "max(besu_blockchain_height) by (cluster)",
        "legendFormat": "{{cluster}}",
        "refId": "A"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "none",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  }
]
EOF
    
    # Add multi-cluster panels to the dashboard
    jq --argjson mcpanels "$(cat /tmp/multi_cluster_panels.json)" '.dashboard.panels += $mcpanels' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
}

# Function to add custom alert views by severity
add_custom_alert_views() {
    local dashboard_json=$1
    
    # Add alert severity variable
    jq '(.dashboard.templating.list) += [{
      "allValue": null,
      "current": {
        "text": "All",
        "value": "$__all"
      },
      "hide": 0,
      "includeAll": true,
      "label": "Alert Severity",
      "multi": true,
      "name": "severity",
      "options": [
        { "selected": true, "text": "Critical", "value": "critical" },
        { "selected": true, "text": "Warning", "value": "warning" },
        { "selected": true, "text": "Info", "value": "info" }
      ],
      "query": "critical,warning,info",
      "skipUrlSync": false,
      "type": "custom"
    }]' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
    
    # Create alert panels
    cat > /tmp/alert_panels.json << 'EOF'
[
  {
    "title": "Active Alerts by Severity",
    "type": "table",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 24, "x": 0, "y": 40 },
    "id": 9,
    "targets": [
      {
        "expr": "ALERTS{alertstate=\"firing\", severity=~\"$severity\", cluster=~\"$cluster\"}",
        "instant": true,
        "format": "table",
        "refId": "A"
      }
    ],
    "transformations": [
      {
        "id": "organize",
        "options": {
          "excludeByName": {
            "Time": true,
            "__name__": true,
            "alertstate": true
          },
          "indexByName": {},
          "renameByName": {
            "alertname": "Alert",
            "instance": "Instance",
            "job": "Job",
            "severity": "Severity",
            "cluster": "Cluster"
          }
        }
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {
          "align": "center",
          "displayMode": "auto",
          "filterable": true
        }
      },
      "overrides": [
        {
          "matcher": {
            "id": "byName",
            "options": "Severity"
          },
          "properties": [
            {
              "id": "custom.displayMode",
              "value": "color-text"
            },
            {
              "id": "mappings",
              "value": [
                {
                  "type": "value",
                  "options": {
                    "critical": {"color": "red", "text": "Critical"},
                    "warning": {"color": "orange", "text": "Warning"},
                    "info": {"color": "blue", "text": "Info"}
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  },
  {
    "title": "Alert Frequency (24h)",
    "type": "bargauge",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 0, "y": 48 },
    "id": 10,
    "options": {
      "orientation": "horizontal",
      "showUnfilled": true
    },
    "targets": [
      {
        "expr": "sum(increase(ALERTS_FOR_STATE{alertstate=\"firing\", severity=\"critical\"}[24h])) or vector(0)",
        "legendFormat": "Critical",
        "refId": "A"
      },
      {
        "expr": "sum(increase(ALERTS_FOR_STATE{alertstate=\"firing\", severity=\"warning\"}[24h])) or vector(0)",
        "legendFormat": "Warning",
        "refId": "B"
      },
      {
        "expr": "sum(increase(ALERTS_FOR_STATE{alertstate=\"firing\", severity=\"info\"}[24h])) or vector(0)",
        "legendFormat": "Info",
        "refId": "C"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "mappings": [],
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            },
            {
              "color": "yellow",
              "value": 5
            },
            {
              "color": "red",
              "value": 10
            }
          ]
        }
      },
      "overrides": [
        {
          "matcher": {
            "id": "byName",
            "options": "Critical"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "red",
                "mode": "fixed"
              }
            }
          ]
        },
        {
          "matcher": {
            "id": "byName",
            "options": "Warning"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "orange",
                "mode": "fixed"
              }
            }
          ]
        },
        {
          "matcher": {
            "id": "byName",
            "options": "Info"
          },
          "properties": [
            {
              "id": "color",
              "value": {
                "fixedColor": "blue",
                "mode": "fixed"
              }
            }
          ]
        }
      ]
    }
  },
  {
    "title": "Alert Resolution Time",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 12, "y": 48 },
    "id": 11,
    "targets": [
      {
        "expr": "avg(besu_alerts_resolution_time_seconds{severity=\"critical\"}) by (alertname)",
        "legendFormat": "Critical - {{alertname}}",
        "refId": "A"
      },
      {
        "expr": "avg(besu_alerts_resolution_time_seconds{severity=\"warning\"}) by (alertname)",
        "legendFormat": "Warning - {{alertname}}",
        "refId": "B"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "s",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  }
]
EOF
    
    # Add alert panels to the dashboard
    jq --argjson alertpanels "$(cat /tmp/alert_panels.json)" '.dashboard.panels += $alertpanels' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
}

# Function to add historical performance trends
add_historical_trends() {
    local dashboard_json=$1
    
    # Create historical trend panels
    cat > /tmp/trend_panels.json << 'EOF'
[
  {
    "title": "CPU Usage Trend (7d)",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 0, "y": 56 },
    "id": 12,
    "options": {
      "legend": {
        "show": true
      }
    },
    "targets": [
      {
        "expr": "avg(rate(node_cpu_seconds_total{mode!=\"idle\",node=~\"$node\"}[1h])) by (instance)",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "percentunit",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  },
  {
    "title": "Memory Usage Trend (7d)",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 12, "x": 12, "y": 56 },
    "id": 13,
    "options": {
      "legend": {
        "show": true
      }
    },
    "targets": [
      {
        "expr": "(node_memory_MemTotal_bytes{node=~\"$node\"} - node_memory_MemAvailable_bytes{node=~\"$node\"}) / node_memory_MemTotal_bytes{node=~\"$node\"}",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "percentunit",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  },
  {
    "title": "Block Production Rate",
    "type": "graph",
    "datasource": "Prometheus",
    "gridPos": { "h": 8, "w": 24, "x": 0, "y": 64 },
    "id": 14,
    "options": {
      "legend": {
        "show": true
      }
    },
    "targets": [
      {
        "expr": "rate(besu_blockchain_height[5m])",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }
    ],
    "fieldConfig": {
      "defaults": {
        "custom": {},
        "unit": "blocks/s",
        "thresholds": {
          "mode": "absolute",
          "steps": [
            {
              "color": "green",
              "value": null
            }
          ]
        }
      }
    }
  }
]
EOF
    
    # Add trend panels to the dashboard
    jq --argjson trendpanels "$(cat /tmp/trend_panels.json)" '.dashboard.panels += $trendpanels' $dashboard_json > /tmp/updated_dashboard.json
    mv /tmp/updated_dashboard.json $dashboard_json
}

# Create the base dashboard
create_base_dashboard

# Add various panel sections based on options
add_cluster_health_metrics "/tmp/enhanced_dashboard.json"

if [[ "$MULTI_CLUSTER" == "true" ]]; then
    add_multi_cluster_view "/tmp/enhanced_dashboard.json"
fi

if [[ "$ALERT_VIEW" == "true" ]]; then
    add_custom_alert_views "/tmp/enhanced_dashboard.json"
fi

if [[ "$TRENDS" == "true" ]]; then
    add_historical_trends "/tmp/enhanced_dashboard.json"
fi

# Install the dashboard to Grafana
echo "Installing enhanced dashboard to Grafana..."
dashboard_response=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s -X POST -H "Content-Type: application/json" -d @- "http://${GRAFANA_API_KEY}@localhost:${GRAFANA_PORT}/api/dashboards/db" < /tmp/enhanced_dashboard.json)

# Verify dashboard was created successfully
if echo "$dashboard_response" | grep -q "id"; then
    dashboard_uid=$(echo "$dashboard_response" | jq -r '.uid')
    echo "✅ Enhanced dashboard created successfully with UID: $dashboard_uid"
    echo "Access dashboard at: http://<grafana-url>/d/$dashboard_uid"
    rm /tmp/enhanced_dashboard.json
    log_audit "monitoring_dashboard_created" "Created enhanced monitoring dashboard with UID: $dashboard_uid with features: ${MULTI_CLUSTER:+multi-cluster }${ALERT_VIEW:+alert-view }${TRENDS:+historical-trends}"
else
    handle_error 201 "Failed to create dashboard: $(echo "$dashboard_response" | jq -r '.message')"
    rm /tmp/enhanced_dashboard.json
    exit 1
fi

echo "Enhanced monitoring dashboard setup complete!"
log_audit "monitoring_dashboard_setup_complete" "Enhanced monitoring dashboard setup completed successfully"
exit 0
