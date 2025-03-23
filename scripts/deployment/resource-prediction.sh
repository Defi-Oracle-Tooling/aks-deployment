#!/bin/bash

# Source deployment utilities
source $(dirname "$0")/deployment-utils.sh

# Initialize logging
setup_logging

# Constants


MONITORING_NAMESPACE="monitoring"
PROMETHEUS_PORT=9090
PREDICTION_WINDOW_DAYS=14
HISTORICAL_DATA_DAYS=30
OUTPUT_DIR="../../monitoring/predictions"
PREDICTION_CONFIG="${PREDICTION_CONFIG:-../../config/common/predictions.json}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Function to gather historical resource usage data from Prometheus
gather_historical_data() {
    local metric=$1
    local days=$2
    local prometheus_pod=$3
    local output_file=$4
    
    echo "Gathering historical data for metric: $metric (last $days days)..."
    
    # Define time range for query
    local end_time=$(date +%s)
    local start_time=$((end_time - days * 24 * 60 * 60))
    
    # Format times for Prometheus
    local end_time_iso=$(date -d @$end_time -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time_iso=$(date -d @$start_time -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Query Prometheus for historical data
    kubectl exec -n "$MONITORING_NAMESPACE" "$prometheus_pod" -- curl -s --data-urlencode "query=$metric" \
        --data-urlencode "start=$start_time_iso" \
        --data-urlencode "end=$end_time_iso" \
        --data-urlencode "step=1h" \
        "http://localhost:${PROMETHEUS_PORT}/api/v1/query_range" > "$output_file"
    
    # Verify we got data
    if jq -e '.data.result | length > 0' "$output_file" > /dev/null; then
        echo "✅ Successfully gathered historical data for $metric"
        return 0
    else
        echo "⚠️ No historical data found for $metric"
        return 1
    fi
}

# Function to perform linear regression for prediction
perform_linear_regression() {
    local data_file=$1
    local output_file=$2
    
    echo "Performing linear regression analysis..."
    
    # Extract the time series data into x,y pairs
    jq -r '.data.result[0].values[] | [.[0], .[1]] | @csv' "$data_file" > "${data_file}.csv"
    
    # Use R (if available) for more sophisticated analysis
    if command -v Rscript &> /dev/null; then
        cat > /tmp/linear_regression.R << 'EOF'
# Read the data
data <- read.csv(commandArgs(trailingOnly = TRUE)[1], header = FALSE)
colnames(data) <- c("timestamp", "value")

# Convert to numeric
data$timestamp <- as.numeric(data$timestamp)
data$value <- as.numeric(data$value)

# Perform linear regression
model <- lm(value ~ timestamp, data = data)

# Get the coefficients
intercept <- coef(model)[1]
slope <- coef(model)[2]

# Calculate prediction for future days
days_ahead <- as.numeric(commandArgs(trailingOnly = TRUE)[2])
seconds_per_day <- 24 * 60 * 60
last_timestamp <- max(data$timestamp)

# Generate prediction points
prediction_times <- seq(last_timestamp, last_timestamp + days_ahead * seconds_per_day, by = seconds_per_day)
predictions <- intercept + slope * prediction_times

# Calculate confidence intervals
pred_interval <- predict(model, newdata = data.frame(timestamp = prediction_times), interval = "prediction", level = 0.95)

# Calculate R-squared and trends
r_squared <- summary(model)$r.squared
trend <- if(slope > 0) "increasing" else if(slope < 0) "decreasing" else "stable"
percent_change_30d <- (predictions[30] - predictions[1]) / predictions[1] * 100

# Output results as JSON
library(jsonlite)
result <- list(
  coefficients = list(intercept = intercept, slope = slope),
  predictions = data.frame(
    timestamp = prediction_times,
    value = predictions,
    lower = pred_interval[, "lwr"],
    upper = pred_interval[, "upr"]
  ),
  stats = list(
    r_squared = r_squared,
    trend = trend,
    percent_change_30d = percent_change_30d
  )
)
write_json(result, commandArgs(trailingOnly = TRUE)[3], pretty = TRUE)
EOF
        
        Rscript /tmp/linear_regression.R "${data_file}.csv" "$PREDICTION_WINDOW_DAYS" "$output_file"
        rm /tmp/linear_regression.R
        
    else
        # Fallback to simple bash/awk calculation if R is not available
        echo "R not found, falling back to simple linear regression with awk..."
        
        awk -F, '
        BEGIN {
            sum_x = 0; sum_y = 0; 
            sum_xy = 0; sum_xx = 0;
            n = 0;
        }
        {
            x = $1;
            y = $2;
            sum_x += x;
            sum_y += y;
            sum_xy += x*y;
            sum_xx += x*x;
            points[n] = x "," y;
            n++;
        }
        END {
            # Simple linear regression formula
            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x);
            intercept = (sum_y - slope * sum_x) / n;
            
            # Calculate R-squared
            sum_sq_total = 0;
            sum_sq_res = 0;
            mean_y = sum_y / n;
            for (i = 0; i < n; i++) {
                split(points[i], p, ",");
                fitted = intercept + slope * p[1];
                sum_sq_total += (p[2] - mean_y)^2;
                sum_sq_res += (p[2] - fitted)^2;
            }
            r_squared = 1 - sum_sq_res / sum_sq_total;
            
            # Create JSON output
            printf "{\n";
            printf "  \"coefficients\": {\n";
            printf "    \"intercept\": %f,\n", intercept;
            printf "    \"slope\": %f\n", slope;
            printf "  },\n";
            printf "  \"predictions\": [\n";
            
            # Get last timestamp
            split(points[n-1], last_point, ",");
            last_timestamp = last_point[1];
            seconds_per_day = 24 * 60 * 60;
            
            for (i = 0; i <= PRED_DAYS; i++) {
                t = last_timestamp + i * seconds_per_day;
                pred = intercept + slope * t;
                printf "    {\"timestamp\": %d, \"value\": %f}", t, pred;
                if (i < PRED_DAYS) printf ",";
                printf "\n";
            }
            
            printf "  ],\n";
            printf "  \"stats\": {\n";
            printf "    \"r_squared\": %f,\n", r_squared;
            printf "    \"trend\": \"%s\",\n", (slope > 0 ? "increasing" : (slope < 0 ? "decreasing" : "stable"));
            
            # Calculate percent change in 30 days
            first_pred = intercept + slope * last_timestamp;
            last_pred = intercept + slope * (last_timestamp + 30 * seconds_per_day);
            percent_change = (last_pred - first_pred) / first_pred * 100;
            printf "    \"percent_change_30d\": %f\n", percent_change;
            
            printf "  }\n";
            printf "}\n";
        }' -v PRED_DAYS=$PREDICTION_WINDOW_DAYS "${data_file}.csv" > "$output_file"
    fi
    
    # Clean up
    rm -f "${data_file}.csv"
    
    echo "✅ Linear regression analysis completed"
    return 0
}

# Function to predict future resource usage
predict_resource_usage() {
    local metric=$1
    local friendly_name=$2
    local prometheus_pod=$3
    
    echo "Predicting future resource usage for $friendly_name..."
    
    # Create temporary files
    local data_file=$(mktemp)
    local output_file="${OUTPUT_DIR}/${friendly_name// /_}_prediction.json"
    
    # Gather historical data
    if ! gather_historical_data "$metric" "$HISTORICAL_DATA_DAYS" "$prometheus_pod" "$data_file"; then
        echo "⚠️ Cannot predict $friendly_name due to insufficient data"
        rm -f "$data_file"
        return 1
    fi
    
    # Perform prediction analysis
    perform_linear_regression "$data_file" "$output_file"
    
    # Clean up
    rm -f "$data_file"
    
    echo "✅ Resource usage prediction for $friendly_name completed"
    echo "   Results saved to $output_file"
    
    return 0
}

# Function to create a Grafana dashboard for predictions
create_prediction_dashboard() {
    echo "Creating prediction dashboard in Grafana..."
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$grafana_pod" ]; then
        handle_error 500 "Grafana pod not found"
        return 1
    fi
    
    # Default Grafana credentials
    local grafana_api_key="${GRAFANA_API_KEY:-admin:admin}"
    
    # Create dashboard JSON
    cat > /tmp/resource-prediction-dashboard.json << EOF
{
  "dashboard": {
    "id": null,
    "uid": "resourceprediction",
    "title": "Resource Usage Predictions",
    "tags": ["besu", "prediction", "resources"],
    "timezone": "browser",
    "schemaVersion": 21,
    "version": 1,
    "refresh": "1h",
    "panels": [
      {
        "title": "CPU Usage Prediction",
        "type": "timeseries",
        "datasource": "Prometheus",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "rate(process_cpu_seconds_total{job=~\".*besu.*\"}[5m])",
            "legendFormat": "Current CPU Usage",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {
            "showLegend": true,
            "displayMode": "table",
            "placement": "bottom"
          }
        }
      },
      {
        "title": "Memory Usage Prediction",
        "type": "timeseries",
        "datasource": "Prometheus",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
        "targets": [
          {
            "expr": "process_resident_memory_bytes{job=~\".*besu.*\"} / 1024 / 1024",
            "legendFormat": "Current Memory Usage (MB)",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {
            "showLegend": true,
            "displayMode": "table",
            "placement": "bottom"
          }
        }
      },
      {
        "title": "Disk Usage Prediction",
        "type": "timeseries",
        "datasource": "Prometheus",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "sum by(persistentvolumeclaim) (kubelet_volume_stats_used_bytes{namespace=\"$namespace\"})",
            "legendFormat": "Current Disk Usage",
            "refId": "A"
          }
        ],
        "options": {
          "legend": {
            "showLegend": true,
            "displayMode": "table",
            "placement": "bottom"
          }
        }
      },
      {
        "title": "Network Usage Prediction",
        "type": "timeseries",
        "datasource": "Prometheus",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "targets": [
          {
            "expr": "sum(rate(container_network_transmit_bytes_total{namespace=\"$namespace\"}[5m]))",
            "legendFormat": "TX",
            "refId": "A"
          },
          {
            "expr": "sum(rate(container_network_receive_bytes_total{namespace=\"$namespace\"}[5m]))",
            "legendFormat": "RX",
            "refId": "B"
          }
        ],
        "options": {
          "legend": {
            "showLegend": true,
            "displayMode": "table",
            "placement": "bottom"
          }
        }
      },
      {
        "title": "Resource Allocation Forecast",
        "type": "table",
        "datasource": "-- Dashboard --",
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
        "options": {
          "showHeader": true
        },
        "fieldConfig": {
          "defaults": {
            "custom": {
              "align": "center"
            }
          },
          "overrides": [
            {
              "matcher": {
                "id": "byName",
                "options": "Trend"
              },
              "properties": [
                {
                  "id": "mappings",
                  "value": [
                    {
                      "type": "value",
                      "options": {
                        "increasing": {"text": "🔼 Increasing", "color": "red"},
                        "decreasing": {"text": "🔽 Decreasing", "color": "green"},
                        "stable": {"text": "◼ Stable", "color": "blue"}
                      }
                    }
                  ]
                }
              ]
            }
          ]
        },
        "transformations": [
          {
            "id": "seriesToColumns",
            "options": {}
          }
        ],
        "pluginVersion": "8.0.0"
      },
      {
        "title": "Resource Planning Guidelines",
        "type": "text",
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 24 },
        "content": "## Resource Planning Guidelines\n\nBased on the prediction models, consider the following recommendations:\n\n- **CPU Allocation**: If the predicted CPU usage in 14 days exceeds 80% of the current allocation, consider increasing CPU resources by 20%.\n- **Memory Allocation**: If the predicted memory usage in 14 days exceeds 75% of the current allocation, consider increasing memory by 30%.\n- **Disk Allocation**: Ensure at least 30% free space will be available in 30 days based on the current growth trend.\n- **Network Capacity**: If network utilization is predicted to grow by more than 50% in 30 days, review network policies and bandwidth allocations.\n\nThese predictions are based on linear regression models and should be periodically reviewed against actual usage patterns.",
        "mode": "markdown"
      }
    ],
    "templating": {
      "list": [
        {
          "allValue": null,
          "current": {
            "text": "besu",
            "value": "besu"
          },
          "datasource": "Prometheus",
          "definition": "label_values(namespace)",
          "hide": 0,
          "includeAll": false,
          "label": "Namespace",
          "multi": false,
          "name": "namespace",
          "options": [],
          "query": {
            "query": "label_values(namespace)",
            "refId": "StandardVariableQuery"
          },
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
      "from": "now-30d",
      "to": "now+14d"
    },
    "timepicker": {
      "refresh_intervals": [
        "15m",
        "30m",
        "1h",
        "2h",
        "6h",
        "12h",
        "1d",
        "2d",
        "7d"
      ]
    }
  },
  "overwrite": true,
  "inputs": [],
  "folderId": 0
}
EOF

    # Install dashboard to Grafana
    echo "Installing prediction dashboard to Grafana..."
    local dashboard_response=$(kubectl exec -n "$MONITORING_NAMESPACE" "$grafana_pod" -- curl -s -X POST -H "Content-Type: application/json" -d @- "http://${grafana_api_key}@localhost:3000/api/dashboards/db" < /tmp/resource-prediction-dashboard.json)
    
    # Check if dashboard was created successfully
    if echo "$dashboard_response" | grep -q "success"; then
        local dashboard_url=$(echo "$dashboard_response" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
        echo "✅ Resource prediction dashboard created successfully"
        echo "Dashboard URL: $dashboard_url"
        rm -f /tmp/resource-prediction-dashboard.json
        return 0
    else
        handle_error 501 "Failed to create resource prediction dashboard: $(echo "$dashboard_response")"
        rm -f /tmp/resource-prediction-dashboard.json
        return 1
    fi
}

# Function to generate prediction report
generate_prediction_report() {
    echo "Generating comprehensive prediction report..."
    
    # Check if we have prediction data
    if [ ! "$(ls -A "$OUTPUT_DIR")" ]; then
        echo "No prediction data found in $OUTPUT_DIR"
        return 1
    fi
    
    # Create report file
    local report_file="${OUTPUT_DIR}/prediction_report_$(date +%Y%m%d).md"
    
    # Generate markdown report
    cat > "$report_file" << EOF
# Resource Usage Prediction Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Summary of Predictions

| Resource | Current Usage | Predicted (14d) | Change % | Trend | Confidence |
|----------|---------------|-----------------|----------|-------|------------|
EOF
    
    # Add predictions to the table
    for pred_file in "$OUTPUT_DIR"/*_prediction.json; do
        [ -f "$pred_file" ] || continue
        
        # Extract resource name from filename
        resource=$(basename "$pred_file" _prediction.json | tr '_' ' ')
        
        # Parse JSON and extract relevant data
        current=$(jq -r '.predictions[0].value' "$pred_file")
        predicted=$(jq -r '.predictions[14].value' "$pred_file")
        percent_change=$(jq -r '.stats.percent_change_30d' "$pred_file")
        trend=$(jq -r '.stats.trend' "$pred_file")
        r_squared=$(jq -r '.stats.r_squared' "$pred_file")
        
        # Format confidence based on R-squared value
        confidence="Low"
        if (( $(echo "$r_squared > 0.7" | bc -l) )); then
            confidence="High"
        elif (( $(echo "$r_squared > 0.5" | bc -l) )); then
            confidence="Medium"
        fi
        
        # Format numbers
        current_fmt=$(printf "%.2f" "$current")
        predicted_fmt=$(printf "%.2f" "$predicted")
        percent_change_fmt=$(printf "%.2f%%" "$percent_change")
        
        # Add row to table
        echo "| $resource | $current_fmt | $predicted_fmt | $percent_change_fmt | $trend | $confidence |" >> "$report_file"
    done
    
    # Add recommendations section
    cat >> "$report_file" << EOF

## Recommendations

Based on the prediction analysis, the following actions are recommended:

EOF
    
    # Generate recommendations based on prediction data
    for pred_file in "$OUTPUT_DIR"/*_prediction.json; do
        [ -f "$pred_file" ] || continue
        
        resource=$(basename "$pred_file" _prediction.json | tr '_' ' ')
        percent_change=$(jq -r '.stats.percent_change_30d' "$pred_file")
        trend=$(jq -r '.stats.trend' "$pred_file")
        
        # Generate recommendation based on resource type and trend
        if [[ "$resource" == *"CPU"* ]]; then
            if (( $(echo "$percent_change > 20" | bc -l) )); then
                echo "- **$resource**: Increase allocation by $(printf "%.0f" "$(echo "$percent_change * 1.2" | bc -l)")% within the next 2 weeks" >> "$report_file"
            elif (( $(echo "$percent_change < -20" | bc -l) )); then
                echo "- **$resource**: Consider reducing allocation by $(printf "%.0f" "$(echo "${percent_change#-} * 0.5" | bc -l)")% to optimize resources" >> "$report_file"
            else
                echo "- **$resource**: No immediate action needed, current allocation is appropriate" >> "$report_file"
            fi
        elif [[ "$resource" == *"Memory"* ]]; then
            if (( $(echo "$percent_change > 15" | bc -l) )); then
                echo "- **$resource**: Increase allocation by $(printf "%.0f" "$(echo "$percent_change * 1.5" | bc -l)")% within the next 2 weeks" >> "$report_file"
            elif (( $(echo "$percent_change < -30" | bc -l) )); then
                echo "- **$resource**: Consider reducing allocation by $(printf "%.0f" "$(echo "${percent_change#-} * 0.4" | bc -l)")% to optimize resources" >> "$report_file"
            else
                echo "- **$resource**: No immediate action needed, current allocation is appropriate" >> "$report_file"
            fi
        elif [[ "$resource" == *"Disk"* || "$resource" == *"Storage"* ]]; then
            if (( $(echo "$percent_change > 10" | bc -l) )); then
                echo "- **$resource**: Plan for storage expansion by $(printf "%.0f" "$(echo "$percent_change * 2" | bc -l)")% within the next month" >> "$report_file"
            else
                echo "- **$resource**: No immediate action needed, current storage is sufficient" >> "$report_file"
            fi
        else
            if [[ "$trend" == "increasing" ]]; then
                echo "- **$resource**: Monitor growth trend, current rate is $(printf "%.2f" "$percent_change")% over 30 days" >> "$report_file"
            else
                echo "- **$resource**: No immediate action needed" >> "$report_file"
            fi
        fi
    done
    
    # Add methodology section
    cat >> "$report_file" << EOF

## Methodology

This prediction report uses linear regression models based on historical data from the last $HISTORICAL_DATA_DAYS days. The confidence level is derived from the R-squared value of each regression model:

- **High**: R-squared > 0.7
- **Medium**: R-squared between 0.5 and 0.7
- **Low**: R-squared < 0.5

For more accurate predictions, consider adjusting the historical data window or implementing more sophisticated time series models.
EOF
    
    echo "✅ Prediction report generated: $report_file"
    return 0
}

# Main function
main() {
    echo "Starting resource usage prediction analysis..."
    
    # Get Prometheus pod
    local prometheus_pod=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus-server -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$prometheus_pod" ]; then
        handle_error 502 "Prometheus pod not found"
        exit 1
    fi
    
    # Clean previous prediction data
    rm -f "$OUTPUT_DIR"/*_prediction.json
    
    # Define metrics to analyze
    declare -A metrics
    metrics["CPU Usage"]="rate(process_cpu_seconds_total{job=~\".*besu.*\"}[5m])"
    metrics["Memory Usage"]="process_resident_memory_bytes{job=~\".*besu.*\"} / 1024 / 1024"  # Convert to MB
    metrics["Disk Usage"]="sum by(persistentvolumeclaim) (kubelet_volume_stats_used_bytes{namespace=\"$NAMESPACE\"})"
    metrics["Network Transmit"]="sum(rate(container_network_transmit_bytes_total{namespace=\"$NAMESPACE\"}[5m]))"
    metrics["Network Receive"]="sum(rate(container_network_receive_bytes_total{namespace=\"$NAMESPACE\"}[5m]))"
    metrics["Transaction Rate"]="rate(besu_transaction_pool_transactions_added_total[5m])"
    metrics["Blockchain Height"]="besu_blockchain_height"
    metrics["Peer Count"]="besu_peers_connected"
    
    # Run predictions for each metric
    for metric_name in "${!metrics[@]}"; do
        predict_resource_usage "${metrics[$metric_name]}" "$metric_name" "$prometheus_pod"
    done
    
    # Create Grafana dashboard
    create_prediction_dashboard
    
    # Generate prediction report
    generate_prediction_report
    
    echo "✅ Resource usage prediction analysis completed"
    log_audit "resource_prediction_completed" "Resource usage prediction analysis completed"
    exit 0
}

# Run main function
main