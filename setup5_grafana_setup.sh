#!/bin/bash

echo "============================================"
echo "Grafana Dashboard Setup with Working Queries"
echo "============================================"
echo ""

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)

echo "Grafana Credentials:"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASSWORD"
echo ""

# Start port-forward
echo "Starting port-forward to Grafana..."
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 5

echo "✓ Port-forward active (PID: $PF_PID)"
echo ""

# Wait for Grafana
echo "Waiting for Grafana to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✓ Grafana is ready"
        break
    fi
    sleep 2
done
echo ""

# Get Prometheus datasource UID
echo "Getting Prometheus datasource..."
DATASOURCE_UID=$(curl -s -u admin:${GRAFANA_PASSWORD} \
  http://localhost:3000/api/datasources 2>/dev/null | \
  jq -r '.[] | select(.type=="prometheus") | .uid' | head -n1)

if [ -z "$DATASOURCE_UID" ]; then
    echo "⚠ Creating Prometheus datasource..."
    RESPONSE=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -u admin:${GRAFANA_PASSWORD} \
      http://localhost:3000/api/datasources \
      -d '{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090",
        "access": "proxy",
        "isDefault": true
      }')
    DATASOURCE_UID=$(echo $RESPONSE | jq -r '.datasource.uid')
fi

echo "✓ Prometheus datasource UID: $DATASOURCE_UID"
echo ""

# Create working dashboard
echo "Creating Falco Security Dashboard with working queries..."

DASHBOARD_JSON=$(cat <<EOF
{
  "dashboard": {
    "id": null,
    "uid": "falco-security-working",
    "title": "Falco Runtime Security (Working)",
    "tags": ["security", "falco", "kubernetes"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 1,
    "refresh": "10s",
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 6, "w": 6, "x": 0, "y": 0},
        "type": "stat",
        "title": "Total Events",
        "targets": [{
          "expr": "sum(falco_events)",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "mappings": [],
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 10, "color": "yellow"},
                {"value": 50, "color": "red"}
              ]
            }
          }
        },
        "options": {
          "colorMode": "value",
          "graphMode": "area",
          "justifyMode": "auto",
          "orientation": "auto",
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"],
            "fields": ""
          }
        }
      },
      {
        "id": 2,
        "gridPos": {"h": 6, "w": 6, "x": 6, "y": 0},
        "type": "stat",
        "title": "Critical Events",
        "targets": [{
          "expr": "sum(falco_events{priority=\"0\"})",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 1, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "gridPos": {"h": 6, "w": 6, "x": 12, "y": 0},
        "type": "stat",
        "title": "Warning Events",
        "targets": [{
          "expr": "sum(falco_events{priority=\"2\"})",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 1, "color": "yellow"}
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "gridPos": {"h": 6, "w": 6, "x": 18, "y": 0},
        "type": "stat",
        "title": "Event Rate (per min)",
        "targets": [{
          "expr": "sum(rate(falco_events[1m])) * 60",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "events/min"
          }
        }
      },
      {
        "id": 5,
        "gridPos": {"h": 10, "w": 12, "x": 0, "y": 6},
        "type": "timeseries",
        "title": "Events Over Time",
        "targets": [{
          "expr": "sum by (priority) (rate(falco_events[1m]))",
          "legendFormat": "Priority {{priority}}",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "fillOpacity": 10,
              "showPoints": "auto"
            }
          }
        }
      },
      {
        "id": 6,
        "gridPos": {"h": 10, "w": 12, "x": 12, "y": 6},
        "type": "piechart",
        "title": "Events by Priority",
        "targets": [{
          "expr": "sum by (priority) (falco_events)",
          "legendFormat": "Priority {{priority}}",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "options": {
          "legend": {
            "displayMode": "table",
            "placement": "right",
            "values": ["value"]
          }
        }
      },
      {
        "id": 7,
        "gridPos": {"h": 10, "w": 24, "x": 0, "y": 16},
        "type": "table",
        "title": "Top Security Rules Triggered",
        "targets": [{
          "expr": "sort_desc(sum by (rule) (falco_events))",
          "format": "table",
          "instant": true,
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "transformations": [
          {
            "id": "organize",
            "options": {
              "excludeByName": {"Time": true},
              "renameByName": {
                "rule": "Rule Name",
                "Value": "Event Count"
              }
            }
          }
        ]
      },
      {
        "id": 8,
        "gridPos": {"h": 10, "w": 12, "x": 0, "y": 26},
        "type": "timeseries",
        "title": "Event Rate by Rule",
        "targets": [{
          "expr": "topk(5, sum by (rule) (rate(falco_events[5m])))",
          "legendFormat": "{{rule}}",
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "drawStyle": "line",
              "fillOpacity": 20,
              "stacking": {"mode": "normal"}
            }
          }
        }
      },
      {
        "id": 9,
        "gridPos": {"h": 10, "w": 12, "x": 12, "y": 26},
        "type": "table",
        "title": "Events by Source",
        "targets": [{
          "expr": "sum by (source) (falco_events)",
          "format": "table",
          "instant": true,
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "$DATASOURCE_UID"}
        }],
        "transformations": [
          {
            "id": "organize",
            "options": {
              "excludeByName": {"Time": true},
              "renameByName": {
                "source": "Event Source",
                "Value": "Count"
              }
            }
          }
        ]
      }
    ],
    "time": {
      "from": "now-6h",
      "to": "now"
    },
    "timepicker": {
      "refresh_intervals": ["5s", "10s", "30s", "1m", "5m"]
    }
  },
  "overwrite": true
}
EOF
)

# Replace datasource UID in JSON
DASHBOARD_JSON=$(echo "$DASHBOARD_JSON" | sed "s/\$DATASOURCE_UID/$DATASOURCE_UID/g")

# Import dashboard
echo "Importing dashboard..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u admin:${GRAFANA_PASSWORD} \
  http://localhost:3000/api/dashboards/db \
  -d "$DASHBOARD_JSON")

DASHBOARD_UID=$(echo $RESPONSE | jq -r '.uid' 2>/dev/null)

if [ "$DASHBOARD_UID" != "null" ] && [ ! -z "$DASHBOARD_UID" ]; then
    echo "✓ Dashboard imported successfully!"
    echo ""
    echo "============================================"
    echo " Dashboard Ready!"
    echo "============================================"
    echo ""
    echo "Access your dashboard:"
    echo "  URL: http://localhost:3000/d/$DASHBOARD_UID"
    echo "  Or navigate: Dashboards → Browse → 'Falco Runtime Security (Working)'"
    echo ""
    echo "Login:"
    echo "  Username: admin"
    echo "  Password: $GRAFANA_PASSWORD"
    echo ""
    echo "The dashboard includes:"
    echo "  ✓ Total Events counter"
    echo "  ✓ Critical/Warning event counts"
    echo "  ✓ Event rate per minute"
    echo "  ✓ Events over time graph"
    echo "  ✓ Events by priority (pie chart)"
    echo "  ✓ Top security rules triggered (table)"
    echo "  ✓ Event rate by rule (stacked graph)"
    echo ""
    echo "Port-forward is running. Press Ctrl+C to stop."
    echo ""
    echo "datasource:http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090"
    # Keep port-forward running
    wait $PF_PID
else
    echo "✗ Error importing dashboard"
    echo "Response: $RESPONSE"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Cleanup

trap "kill $PF_PID 2>/dev/null || true" EXIT
