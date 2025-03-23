#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants
NAMESPACE="besu"
MONITORING_NAMESPACE="monitoring"
PROMETHEUS_PORT=9090
ANOMALY_CONFIG="${ANOMALY_CONFIG:-../../config/common/anomaly_detection.json}"
OUTPUT_DIR="../../monitoring/anomalies"
ALERT_THRESHOLD=3.0  # Number of standard deviations for anomaly detection
LOOKBACK_WINDOW=12h  # Time window for analysis
ANOMALY_PERSISTENCE_DAYS=7  # How long to keep anomaly data

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Function to detect anomalies using Z-score method
detect_zscore_anomalies() {
    local metric=$1
    local description=$2
    local prometheus_pod=$3
    local output_file=$4
    
    echo "Detecting anomalies for $description using Z-score method..."
    
    # Query Prometheus for metric data
    local query_result=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=$metric[${LOOKBACK_WINDOW}]" "http://localhost:${PROMETHEUS_PORT}/api/v1/query")
    
    # Check if we have data
    if ! echo "$query_result" | jq -e '.data.result | length > 0' > /dev/null; then
        echo "⚠️ No data found for metric: $metric"
        return 1
    fi
    
    # Extract values
    local values=$(echo "$query_result" | jq -r '.data.result[0].values[] | .[1]')
    
    # Calculate mean and standard deviation
    local stats=$(echo "$values" | awk '
    {
        sum += $1
        sumsq += $1 * $1
        count++
    }
    END {
        mean = sum / count
        stddev = sqrt((sumsq - (sum * sum) / count) / (count - 1))
        print mean " " stddev " " count
    }')
    
    local mean=$(echo "$stats" | awk '{print $1}')
    local stddev=$(echo "$stats" | awk '{print $2}')
    local count=$(echo "$stats" | awk '{print $3}')
    
    # Return if we don't have enough data points
    if [[ $count -lt 10 ]]; then
        echo "⚠️ Not enough data points for anomaly detection (found $count, need at least 10)"
        return 1
    fi
    
    # Find anomalies (values outside ALERT_THRESHOLD standard deviations)
    local threshold_upper=$(echo "$mean + ($ALERT_THRESHOLD * $stddev)" | bc -l)
    local threshold_lower=$(echo "$mean - ($ALERT_THRESHOLD * $stddev)" | bc -l)
    
    # Extract timestamps with values
    local timestamps_values=$(echo "$query_result" | jq -r '.data.result[0].values[] | "[\(.[0]), \(.[1])]"')
    
    # Identify anomalies
    local anomalies=$(echo "$timestamps_values" | while read -r line; do
        timestamp=$(echo "$line" | jq -r '.[0]')
        value=$(echo "$line" | jq -r '.[1]')
        
        if (( $(echo "$value > $threshold_upper" | bc -l) )) || (( $(echo "$value < $threshold_lower" | bc -l) )); then
            deviation=$(echo "scale=2; ($value - $mean) / $stddev" | bc)
            echo "{\"timestamp\": $timestamp, \"value\": $value, \"deviation\": $deviation}"
        fi
    done)
    
    # If we found anomalies, save them
    if [[ -n "$anomalies" ]]; then
        # Create JSON report
        cat > "$output_file" << EOF
{
  "metric": "$metric",
  "description": "$description",
  "analysis_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "lookback_window": "${LOOKBACK_WINDOW}",
  "stats": {
    "mean": $mean,
    "stddev": $stddev,
    "count": $count,
    "upper_threshold": $threshold_upper,
    "lower_threshold": $threshold_lower
  },
  "anomalies": [
    $(echo "$anomalies" | paste -sd "," -)
  ]
}
EOF
        
        # Count anomalies
        local anomaly_count=$(echo "$anomalies" | wc -l | tr -d ' ')
        echo "✅ Found $anomaly_count anomalies for $description"
        return 0
    else
        echo "✅ No anomalies detected for $description"
        echo "{}" > "$output_file"
        return 0
    fi
}

# Function to detect anomalies using moving average method
detect_moving_avg_anomalies() {
    local metric=$1
    local description=$2
    local prometheus_pod=$3
    local output_file=$4
    local window_size=${5:-5}  # Default window size for moving average
    
    echo "Detecting anomalies for $description using moving average method..."
    
    # Query Prometheus for metric data with step size
    local step="1m"
    local query_result=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=$metric[${LOOKBACK_WINDOW}:${step}]" "http://localhost:${PROMETHEUS_PORT}/api/v1/query")
    
    # Check if we have data
    if ! echo "$query_result" | jq -e '.data.result | length > 0' > /dev/null; then
        echo "⚠️ No data found for metric: $metric"
        return 1
    fi
    
    # Extract timestamps and values
    local timestamps_values=$(echo "$query_result" | jq -r '.data.result[0].values[] | "[\(.[0]), \(.[1])]"')
    
    # Create a temporary file to store the data
    local temp_file=$(mktemp)
    echo "$timestamps_values" > "$temp_file"
    
    # Process with awk to find moving average anomalies
    local anomalies=$(awk -v window=$window_size -v threshold=$ALERT_THRESHOLD '
    BEGIN {
        count = 0;
    }
    
    function abs(x) {
        return (x < 0) ? -x : x;
    }
    
    {
        gsub(/[\[\]]/, "", $0);  # Remove brackets
        timestamp = $1;
        value = $2;
        
        # Store data point
        times[count] = timestamp;
        values[count] = value;
        count++;
        
        # Need at least window*2 points to detect anomalies
        if (count >= window*2) {
            # Calculate moving average for previous window
            prev_sum = 0;
            for (i = count - window*2; i < count - window; i++) {
                prev_sum += values[i];
            }
            prev_avg = prev_sum / window;
            
            # Calculate moving average for current window
            current_sum = 0;
            for (i = count - window; i < count; i++) {
                current_sum += values[i];
            }
            current_avg = current_sum / window;
            
            # Calculate percent change
            if (prev_avg != 0) {
                pct_change = abs((current_avg - prev_avg) / prev_avg * 100);
                
                # If percent change exceeds threshold, report anomaly
                if (pct_change > threshold * 10) {  # Convert stddev threshold to percent
                    printf "{\"timestamp\": %.0f, \"value\": %s, \"deviation\": %.2f, \"pct_change\": %.2f}\n", 
                        times[count-1], values[count-1], (values[count-1] - current_avg) / current_avg, pct_change;
                }
            }
        }
    }' "$temp_file")
    
    # Remove temporary file
    rm -f "$temp_file"
    
    # Calculate basic statistics for the entire dataset
    local stats=$(echo "$timestamps_values" | jq -r '.[1]' | awk '
    {
        sum += $1
        sumsq += $1 * $1
        count++
        if (min == "" || $1 < min) min = $1
        if (max == "" || $1 > max) max = $1
    }
    END {
        mean = sum / count
        stddev = sqrt((sumsq - (sum * sum) / count) / (count - 1))
        print min " " max " " mean " " stddev " " count
    }')
    
    local min=$(echo "$stats" | awk '{print $1}')
    local max=$(echo "$stats" | awk '{print $2}')
    local mean=$(echo "$stats" | awk '{print $3}')
    local stddev=$(echo "$stats" | awk '{print $4}')
    local count=$(echo "$stats" | awk '{print $5}')
    
    # If we found anomalies, save them
    if [[ -n "$anomalies" ]]; then
        # Create JSON report
        cat > "$output_file" << EOF
{
  "metric": "$metric",
  "description": "$description",
  "analysis_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "lookback_window": "${LOOKBACK_WINDOW}",
  "window_size": $window_size,
  "stats": {
    "min": $min,
    "max": $max,
    "mean": $mean,
    "stddev": $stddev,
    "count": $count
  },
  "method": "moving_average",
  "anomalies": [
    $(echo "$anomalies" | paste -sd "," -)
  ]
}
EOF
        
        # Count anomalies
        local anomaly_count=$(echo "$anomalies" | wc -l | tr -d ' ')
        echo "✅ Found $anomaly_count anomalies for $description using moving average method"
        return 0
    else
        echo "✅ No anomalies detected for $description using moving average method"
        echo "{}" > "$output_file"
        return 0
    fi
}

# Function to detect seasonality patterns
detect_seasonality() {
    local metric=$1
    local description=$2
    local prometheus_pod=$3
    local output_file=$4
    
    echo "Analyzing seasonality patterns for $description..."
    
    # Use a longer window for seasonality detection (24h)
    local seasonality_window="24h"
    
    # Query Prometheus for metric data with 1-minute steps
    local query_result=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=$metric[${seasonality_window}:1m]" "http://localhost:${PROMETHEUS_PORT}/api/v1/query")
    
    # Check if we have data
    if ! echo "$query_result" | jq -e '.data.result | length > 0' > /dev/null; then
        echo "⚠️ No data found for metric: $metric"
        return 1
    fi
    
    # Extract timestamps and values
    local timestamps_values=$(echo "$query_result" | jq -r '.data.result[0].values[] | "[\(.[0]), \(.[1])]"')
    
    # Create a temporary file to store the data
    local temp_file=$(mktemp)
    echo "$timestamps_values" > "$temp_file"
    
    # Use R for seasonality detection if available
    if command -v Rscript &> /dev/null; then
        cat > /tmp/seasonality.R << 'EOF'
# Load necessary libraries
if (!require("forecast")) {
  install.packages("forecast", repos="https://cran.r-project.org")
  library(forecast)
}
if (!require("jsonlite")) {
  install.packages("jsonlite", repos="https://cran.r-project.org")
  library(jsonlite)
}

# Read the data
args <- commandArgs(trailingOnly = TRUE)
data_file <- args[1]
output_file <- args[2]
metric <- args[3]
description <- args[4]

# Load data
data <- read.table(data_file)
values <- as.numeric(data$V2)
timestamps <- as.numeric(data$V1)

# Create time series object
ts_data <- ts(values, frequency=60)  # Assuming 1 minute data, 60 points per hour

# Decompose time series to find seasonality
result <- NULL
tryCatch({
  # Try STL decomposition
  decomp <- stl(ts_data, s.window="periodic")
  seasonal <- decomp$time.series[,"seasonal"]
  trend <- decomp$time.series[,"trend"]
  remainder <- decomp$time.series[,"remainder"]
  
  # Calculate strength of seasonality
  var_seas <- var(seasonal, na.rm=TRUE)
  var_rem <- var(remainder, na.rm=TRUE)
  strength_seasonality <- max(0, 1 - var_rem / (var_seas + var_rem))
  
  # Auto-correlation to identify period
  acf_result <- acf(ts_data, lag.max=120, plot=FALSE)  # Up to 2 hours lag
  acf_values <- acf_result$acf[-1]  # Remove lag 0
  periods <- which(acf_values > 0.3)  # Significant correlation threshold
  
  # Find the dominant periods
  if(length(periods) > 0) {
    dominant_periods <- periods[order(acf_values[periods], decreasing=TRUE)[1:min(3, length(periods))]]
  } else {
    dominant_periods <- integer(0)
  }
  
  result <- list(
    metric = metric,
    description = description,
    analysis_time = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    seasonality = list(
      detected = strength_seasonality > 0.3,
      strength = strength_seasonality,
      dominant_periods = dominant_periods,
      interpretation = ifelse(
        strength_seasonality > 0.3,
        paste0("Strong seasonality detected with period(s): ", 
               paste(dominant_periods, collapse=", "), " minutes"),
        "No significant seasonality detected"
      )
    ),
    stats = list(
      mean = mean(values, na.rm=TRUE),
      min = min(values, na.rm=TRUE),
      max = max(values, na.rm=TRUE),
      count = length(values)
    ),
    method = "stl_decomposition"
  )
}, error=function(e) {
  # Fallback to basic statistics if decomposition fails
  result <<- list(
    metric = metric,
    description = description,
    analysis_time = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    seasonality = list(
      detected = FALSE,
      strength = 0,
      dominant_periods = integer(0),
      interpretation = paste0("Could not detect seasonality: ", e$message)
    ),
    stats = list(
      mean = mean(values, na.rm=TRUE),
      min = min(values, na.rm=TRUE),
      max = max(values, na.rm=TRUE),
      count = length(values)
    ),
    method = "basic_statistics"
  )
})

# Write the result to JSON file
write_json(result, output_file, pretty=TRUE)
EOF
        
        # Run R script for seasonality detection
        Rscript /tmp/seasonality.R "$temp_file" "$output_file" "$metric" "$description"
        rm -f /tmp/seasonality.R
        
        # Check if we successfully detected seasonality
        if jq -e '.seasonality.detected' "$output_file" > /dev/null; then
            echo "✅ Seasonality analysis completed for $description"
            local strength=$(jq -r '.seasonality.strength' "$output_file")
            local periods=$(jq -r '.seasonality.dominant_periods | join(", ")' "$output_file")
            echo "   Seasonality strength: $strength, Dominant periods: $periods minutes"
        else
            echo "⚠️ No significant seasonality detected for $description"
        fi
        
    else
        # Fallback to basic frequency analysis if R is not available
        echo "R not available, falling back to basic frequency analysis..."
        
        # Use AWK to detect basic patterns
        local hour_patterns=$(awk '
        BEGIN {
            for (i=0; i<24; i++) hour_count[i] = 0;
            for (i=0; i<24; i++) hour_sum[i] = 0;
        }
        {
            gsub(/[\[\]]/, "", $0);  # Remove brackets
            timestamp = $1;
            value = $2;
            
            # Extract hour from timestamp
            hour = int((timestamp % 86400) / 3600);
            
            hour_count[hour]++;
            hour_sum[hour] += value;
        }
        END {
            for (i=0; i<24; i++) {
                if (hour_count[i] > 0) {
                    printf "%d,%.6f\n", i, hour_sum[i] / hour_count[i];
                } else {
                    printf "%d,0\n", i;
                }
            }
        }' "$temp_file")
        
        # Create JSON report
        cat > "$output_file" << EOF
{
  "metric": "$metric",
  "description": "$description",
  "analysis_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "seasonality": {
    "detected": false,
    "strength": 0,
    "hour_patterns": [
      $(echo "$hour_patterns" | awk -F, '{printf "{\"hour\": %d, \"average_value\": %s}", $1, $2; if (NR<24) printf ","; printf "\n"}' | paste -sd " " -)
    ],
    "interpretation": "Basic hour-based pattern analysis only (R not available for full seasonality detection)"
  },
  "method": "basic_hour_analysis"
}
EOF
        
        echo "⚠️ Limited seasonality analysis completed for $description (R not available)"
    fi
    
    # Remove temporary file
    rm -f "$temp_file"
    return 0
}

# Function to detect anomalies in consensus metrics
detect_consensus_anomalies() {
    local prometheus_pod=$1
    local output_dir=$2
    
    echo "Analyzing Besu consensus metrics for anomalies..."
    
    # Check if we have consensus metrics
    local has_consensus=$(kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=besu_consensus_executed_block_proposals_total" "http://localhost:${PROMETHEUS_PORT}/api/v1/query" | jq -r '.data.result | length')
    
    if [[ "$has_consensus" -eq 0 ]]; then
        echo "⚠️ No consensus metrics found, skipping consensus anomaly detection"
        return 0
    fi
    
    # Define consensus-specific metrics
    local metrics=(
        "besu_consensus_executed_block_proposals_total"
        "besu_consensus_proposed_blocks_total"
        "besu_consensus_missed_block_proposals_total"
        "besu_consensus_head_slot"
        "besu_consensus_reorgs_total"
        "besu_consensus_finalized_epoch"
    )
    
    local descriptions=(
        "Executed Block Proposals"
        "Proposed Blocks"
        "Missed Block Proposals"
        "Head Slot"
        "Reorgs"
        "Finalized Epoch"
    )
    
    # Detect anomalies for each metric
    for i in "${!metrics[@]}"; do
        local metric="${metrics[$i]}"
        local description="${descriptions[$i]}"
        local output_file="${output_dir}/consensus_${metric//besu_consensus_/}_anomalies.json"
        
        # Use different methods based on metric type
        if [[ "$metric" == *"_total" ]]; then
            # Use rate for counter metrics
            detect_zscore_anomalies "rate(${metric}[5m])" "Consensus ${description} Rate" "$prometheus_pod" "$output_file"
            
            # For important metrics like missed proposals, also check for moving average
            if [[ "$metric" == *"missed"* || "$metric" == *"reorgs"* ]]; then
                local ma_output_file="${output_dir}/consensus_${metric//besu_consensus_/}_ma_anomalies.json"
                detect_moving_avg_anomalies "rate(${metric}[5m])" "Consensus ${description} Rate" "$prometheus_pod" "$ma_output_file" 10
            fi
        else
            # Use raw values for gauge metrics
            detect_zscore_anomalies "${metric}" "Consensus ${description}" "$prometheus_pod" "$output_file"
            
            # Check for seasonality in head slot and finalized epoch
            if [[ "$metric" == *"head_slot"* || "$metric" == *"finalized_epoch"* ]]; then
                local seasonality_file="${output_dir}/consensus_${metric//besu_consensus_/}_seasonality.json"
                detect_seasonality "${metric}" "Consensus ${description}" "$prometheus_pod" "$seasonality_file"
            fi
        fi
    done
    
    # Special analysis: Check finality delay
    local output_file="${output_dir}/consensus_finality_delay_anomalies.json"
    detect_zscore_anomalies "(besu_consensus_head_slot - besu_consensus_finalized_epoch * 32)" "Consensus Finality Delay" "$prometheus_pod" "$output_file"
    
    echo "✅ Consensus metrics anomaly detection completed"
    return 0
}

# Function to create Grafana dashboard for anomalies
create_anomaly_dashboard() {
    echo "Creating anomaly detection dashboard in Grafana..."
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$grafana_pod" ]; then
        handle_error 500 "Grafana pod not found"
        return 1
    fi
    
    # Default Grafana credentials
    local grafana_api_key="${GRAFANA_API_KEY:-admin:admin}"
    
    # Create dashboard JSON
    cat > /tmp/anomaly-detection-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "besuanomalydetection",
    "title": "Besu Anomaly Detection",
    "tags": ["besu", "anomaly", "monitoring"],
    "timezone": "browser",
    "schemaVersion": 21,
    "version": 1,
    "refresh": "5m",
    "panels": [
      {
        "title": "Anomaly Status Overview",
        "type": "gauge",
        "gridPos": {
          "h": 8,
          "w": 6,
          "x": 0,
          "y": 0
        },
        "id": 1,
        "targets": [
          {
            "expr": "sum(increase(besu_anomaly_detection_anomalies_total[1h]))",
            "refId": "A"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": [
              "lastNotNull"
            ],
            "fields": ""
          },
          "orientation": "auto",
          "showThresholdLabels": false,
          "showThresholdMarkers": true
        },
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
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
                  "value": 1
                },
                {
                  "color": "orange",
                  "value": 5
                },
                {
                  "color": "red",
                  "value": 10
                }
              ]
            }
          }
        }
      },
      {
        "title": "Transaction Rate Anomalies",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 18,
          "x": 6,
          "y": 0
        },
        "id": 2,
        "targets": [
          {
            "expr": "rate(besu_transaction_pool_transactions_added_total[5m])",
            "legendFormat": "Transaction Rate",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "lineInterpolation": "linear",
              "spanNulls": true
            }
          }
        },
        "options": {
          "legend": {
            "showLegend": true,
            "displayMode": "list",
            "placement": "bottom"
          }
        }
      },
      {
        "title": "Recent Anomaly Events",
        "type": "table",
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 8
        },
        "id": 3,
        "targets": [
          {
            "expr": "besu_anomaly_detection_events",
            "format": "table",
            "instant": true,
            "refId": "A"
          }
        ],
        "transformations": [
          {
            "id": "organize",
            "options": {
              "excludeByName": {
                "__name__": true,
                "job": true,
                "instance": true
              },
              "indexByName": {},
              "renameByName": {}
            }
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "align": "auto"
            }
          }
        }
      },
      {
        "title": "Network Metrics",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 16
        },
        "id": 4,
        "targets": [
          {
            "expr": "besu_peers_connected",
            "legendFormat": "Connected Peers",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "lineInterpolation": "linear",
              "spanNulls": true
            }
          }
        }
      },
      {
        "title": "Blockchain Metrics",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 16
        },
        "id": 5,
        "targets": [
          {
            "expr": "besu_blockchain_height",
            "legendFormat": "Block Height",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "lineInterpolation": "linear",
              "spanNulls": true
            }
          }
        }
      },
      {
        "title": "Consensus Metrics",
        "type": "timeseries",
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 24
        },
        "id": 6,
        "targets": [
          {
            "expr": "rate(besu_consensus_executed_block_proposals_total[5m])",
            "legendFormat": "Executed Proposals Rate",
            "refId": "A"
          },
          {
            "expr": "rate(besu_consensus_missed_block_proposals_total[5m])",
            "legendFormat": "Missed Proposals Rate",
            "refId": "B"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "lineInterpolation": "linear",
              "spanNulls": true
            }
          }
        }
      },
      {
        "title": "Anomaly Detection Documentation",
        "type": "text",
        "gridPos": {
          "h": 4,
          "w": 24,
          "x": 0,
          "y": 32
        },
        "id": 7,
        "content": "## Anomaly Detection\n\nThis dashboard presents metrics with automated anomaly detection applied. Anomalies are detected using statistical methods like Z-score analysis and moving averages.\n\n- **Green**: No anomalies detected\n- **Yellow**: Minor anomalies detected\n- **Orange**: Significant anomalies detected\n- **Red**: Critical anomalies detected\n\nFor more information, consult the anomaly detection logs or the documentation.",
        "mode": "markdown"
      }
    ],
    "templating": {
      "list": []
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
      ]
    }
  },
  "overwrite": true,
  "inputs": [],
  "folderId": 0
}
EOF
    
    # Install dashboard to Grafana
    echo "Installing anomaly detection dashboard to Grafana..."
    local dashboard_response=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s -X POST -H "Content-Type: application/json" -d @- "http://${grafana_api_key}@localhost:3000/api/dashboards/db" < /tmp/anomaly-detection-dashboard.json)
    
    # Check if dashboard was created successfully
    if echo "$dashboard_response" | grep -q "success"; then
        local dashboard_url=$(echo "$dashboard_response" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
        echo "✅ Anomaly detection dashboard created successfully"
        echo "Dashboard URL: $dashboard_url"
        rm -f /tmp/anomaly-detection-dashboard.json
        return 0
    else
        handle_error 501 "Failed to create anomaly detection dashboard: $(echo "$dashboard_response")"
        rm -f /tmp/anomaly-detection-dashboard.json
        return 1
    fi
}

# Function to generate anomaly detection report
generate_anomaly_report() {
    local output_dir=$1
    echo "Generating anomaly detection report..."
    
    # Create report file
    local report_file="${output_dir}/anomaly_report_$(date +%Y%m%d).md"
    
    # Generate markdown report header
    cat > "$report_file" << EOF
# Besu Anomaly Detection Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Summary of Detected Anomalies

| Metric | Anomalies | Severity | Details |
|--------|-----------|----------|---------|
EOF
    
    # Check if we have anomaly data
    if [ ! "$(ls -A "$output_dir")" ]; then
        echo "No anomaly data found in $output_dir"
        echo "No anomalies detected." >> "$report_file"
        return 1
    fi
    
    # Collect all anomalies
    local total_anomalies=0
    local critical_anomalies=0
    
    # Process each anomaly file
    for anomaly_file in "$output_dir"/*_anomalies.json; do
        [ -f "$anomaly_file" ] || continue
        
        # Skip empty anomaly files
        if [[ "$(jq 'length' "$anomaly_file")" == "0" ]]; then
            continue
        fi
        
        # Extract metric information
        local description=$(jq -r '.description // ""' "$anomaly_file")
        if [[ -z "$description" ]]; then
            description=$(basename "$anomaly_file" _anomalies.json | tr '_' ' ' | sed -e 's/^./\U&/g' -e 's/ ./\U&/g')
        fi
        
        # Count anomalies in this file
        local anomaly_count=$(jq -r '.anomalies | length // 0' "$anomaly_file")
        if [[ -z "$anomaly_count" || "$anomaly_count" == "null" ]]; then
            anomaly_count=0
        fi
        
        total_anomalies=$((total_anomalies + anomaly_count))
        
        # Skip if no anomalies
        if [[ "$anomaly_count" -eq 0 ]]; then
            continue
        fi
        
        # Determine severity based on anomaly count and max deviation
        local max_deviation=$(jq -r '.anomalies | map(.deviation) | max // 0' "$anomaly_file")
        local severity="Low"
        
        if (( $(echo "$max_deviation > 10" | bc -l) )); then
            severity="Critical"
            critical_anomalies=$((critical_anomalies + 1))
        elif (( $(echo "$max_deviation > 5" | bc -l) )); then
            severity="High"
        elif (( $(echo "$max_deviation > 3" | bc -l) )); then
            severity="Medium"
        fi
        
        # Get details about the anomalies
        local latest_anomaly_time=$(jq -r '.anomalies | sort_by(.timestamp) | reverse[0].timestamp // 0' "$anomaly_file")
        local latest_anomaly_time_fmt="N/A"
        
        if [[ "$latest_anomaly_time" != "0" && "$latest_anomaly_time" != "null" ]]; then
            latest_anomaly_time_fmt=$(date -d @"$latest_anomaly_time" "+%Y-%m-%d %H:%M:%S UTC")
        fi
        
        # Format details
        local details="Latest: $latest_anomaly_time_fmt, Max Deviation: $(printf "%.2f" "$max_deviation")"
        
        # Add row to table
        echo "| $description | $anomaly_count | $severity | $details |" >> "$report_file"
    done
    
    # Add seasonality information
    echo -e "\n## Detected Seasonality Patterns\n" >> "$report_file"
    
    for seasonality_file in "$output_dir"/*_seasonality.json; do
        [ -f "$seasonality_file" ] || continue
        
        local description=$(jq -r '.description // ""' "$seasonality_file")
        local detected=$(jq -r '.seasonality.detected // false' "$seasonality_file")
        local interpretation=$(jq -r '.seasonality.interpretation // "No interpretation available"' "$seasonality_file")
        
        if [[ "$detected" == "true" ]]; then
            local strength=$(jq -r '.seasonality.strength // 0' "$seasonality_file")
            echo "### $description" >> "$report_file"
            echo "- **Seasonality Detected**: Yes" >> "$report_file"
            echo "- **Strength**: $(printf "%.2f" "$strength")" >> "$report_file"
            echo "- **Interpretation**: $interpretation" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    # Add summary section
    cat >> "$report_file" << EOF

## Summary

- **Total Anomalies Detected**: $total_anomalies
- **Critical Anomalies**: $critical_anomalies
- **Analysis Period**: Last ${LOOKBACK_WINDOW}
- **Detection Threshold**: $ALERT_THRESHOLD standard deviations from mean

## Recommendations

EOF
    
    # Add recommendations based on findings
    if [[ $critical_anomalies -gt 0 ]]; then
        cat >> "$report_file" << EOF
- **URGENT**: Investigate critical anomalies immediately. These represent significant deviations from normal operation.
- Review system logs during the anomaly periods for additional context.
- Consider adjusting alert thresholds if these are expected variations.
EOF
    elif [[ $total_anomalies -gt 5 ]]; then
        cat >> "$report_file" << EOF
- **HIGH PRIORITY**: Multiple anomalies detected. Schedule investigation within 24 hours.
- Check for any recent configuration changes or network events.
- Monitor these metrics closely over the next few days.
EOF
    elif [[ $total_anomalies -gt 0 ]]; then
        cat >> "$report_file" << EOF
- **MODERATE**: A few anomalies detected. Monitor the affected metrics.
- Consider reviewing these during the next scheduled maintenance window.
- No immediate action required if system performance is not impacted.
EOF
    else
        cat >> "$report_file" << EOF
- **NORMAL**: No anomalies detected. System is operating within expected parameters.
- Continue regular monitoring and anomaly detection.
EOF
    fi
    
    # Add methodology section
    cat >> "$report_file" << EOF

## Methodology

This anomaly detection report uses multiple statistical methods:

1. **Z-score Analysis**: Identifies values that fall outside $ALERT_THRESHOLD standard deviations from the mean
2. **Moving Average**: Detects sudden changes in trends by comparing consecutive moving averages
3. **Seasonality Detection**: Analyzes time series data for recurring patterns

Data is analyzed over a ${LOOKBACK_WINDOW} window to establish baselines and identify outliers.
EOF
    
    echo "✅ Anomaly detection report generated: $report_file"
    
    # If we found critical anomalies, return non-zero to indicate attention needed
    if [[ $critical_anomalies -gt 0 ]]; then
        return 2
    elif [[ $total_anomalies -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Function to clean up old anomaly files
cleanup_old_anomaly_files() {
    echo "Cleaning up old anomaly files..."
    
    # Convert days to seconds
    local max_age_seconds=$((ANOMALY_PERSISTENCE_DAYS * 86400))
    local current_time=$(date +%s)
    
    # Find and remove old files
    find "$OUTPUT_DIR" -type f -name "*_anomalies.json" -o -name "*_seasonality.json" -o -name "anomaly_report_*.md" | while read file; do
        # Get file modification time
        local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")
        local file_age=$((current_time - file_time))
        
        if [[ $file_age -gt $max_age_seconds ]]; then
            echo "Removing old file: $file"
            rm -f "$file"
        fi
    done
    
    echo "✅ Cleanup completed"
    return 0
}

# Main function
main() {
    echo "Starting Besu anomaly detection..."
    
    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"
    
    # Clean up old files
    cleanup_old_anomaly_files
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$prometheus_pod" ]; then
        handle_error 510 "Prometheus pod not found"
        exit 1
    fi
    
    # Define metrics to analyze
    declare -A metrics
    metrics["Transaction Rate"]="rate(besu_transaction_pool_transactions_added_total[5m])"
    metrics["Block Import Rate"]="rate(besu_blockchain_chain_head_gas_used[5m])"
    metrics["Block Creation Time"]="besu_blockchain_chain_head_timestamp"
    metrics["Connected Peers"]="besu_peers_connected"
    metrics["RPC Request Rate"]="rate(besu_rpc_request_duration_count[5m])"
    metrics["P2P Message Rate"]="rate(besu_network_messages_out_total[5m])"
    metrics["Memory Usage"]="process_resident_memory_bytes{job=~\".*besu.*\"}"
    metrics["CPU Usage"]="rate(process_cpu_seconds_total{job=~\".*besu.*\"}[5m])"
    
    # Create timestamp for this analysis run
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local run_dir="$OUTPUT_DIR/run_$timestamp"
    mkdir -p "$run_dir"
    
    # Run anomaly detection for each metric
    for metric_name in "${!metrics[@]}"; do
        # Z-score method
        local output_file="$run_dir/${metric_name// /_}_anomalies.json"
        detect_zscore_anomalies "${metrics[$metric_name]}" "$metric_name" "$prometheus_pod" "$output_file"
        
        # For some metrics, also use moving average method
        if [[ "$metric_name" == "Transaction Rate" || "$metric_name" == "Block Import Rate" ]]; then
            local ma_output_file="$run_dir/${metric_name// /_}_ma_anomalies.json"
            detect_moving_avg_anomalies "${metrics[$metric_name]}" "$metric_name" "$prometheus_pod" "$ma_output_file"
        fi
        
        # For time-based metrics, check for seasonality
        if [[ "$metric_name" == "Block Creation Time" || "$metric_name" == "Transaction Rate" ]]; then
            local seasonality_file="$run_dir/${metric_name// /_}_seasonality.json"
            detect_seasonality "${metrics[$metric_name]}" "$metric_name" "$prometheus_pod" "$seasonality_file"
        fi
    done
    
    # Detect consensus anomalies if consensus metrics are available
    detect_consensus_anomalies "$prometheus_pod" "$run_dir"
    
    # Create Grafana dashboard
    create_anomaly_dashboard
    
    # Generate report
    generate_anomaly_report "$run_dir"
    result=$?
    
    # Symlink the latest run for easy access
    ln -sf "run_$timestamp" "$OUTPUT_DIR/latest"
    
    # Log completion
    if [[ $result -eq 2 ]]; then
        log_audit "anomaly_detection_critical" "Anomaly detection completed with CRITICAL anomalies found"
        echo "❗ Anomaly detection completed with CRITICAL anomalies found"
        exit 2
    elif [[ $result -eq 1 ]]; then
        log_audit "anomaly_detection_warning" "Anomaly detection completed with anomalies found"
        echo "⚠️ Anomaly detection completed with anomalies found"
        exit 1
    else
        log_audit "anomaly_detection_normal" "Anomaly detection completed, no anomalies found"
        echo "✅ Anomaly detection completed, no anomalies found"
        exit 0
    fi
}

# Run main function
main