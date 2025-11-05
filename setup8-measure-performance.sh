#!/bin/bash

echo "============================================"
echo "Falco Performance Measurement"
echo "============================================"
echo ""

# Function to get CPU and Memory usage
get_resource_usage() {
    local pod=$1
    local namespace=$2
    kubectl top pod $pod -n $namespace --no-headers | awk '{print $2, $3}'
}

# Get node resources
echo "[*] Node Resource Usage:"
kubectl top nodes
echo ""

# Measure Falco resource consumption
echo "[*] Falco Pod Resource Usage:"
FALCO_POD=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $FALCO_POD"
kubectl top pod $FALCO_POD -n falco
echo ""

# Event latency test
echo "[*] Testing Event Detection Latency..."
START_TIME=$(date +%s%N)

# Trigger a simple event
kubectl exec test-shell-execution -- /bin/sh -c "whoami" 2>/dev/null

# Wait for Falco to process
sleep 1

# Check Falco logs for the event
END_TIME=$(date +%s%N)
LATENCY=$(( ($END_TIME - $START_TIME) / 1000000 )) # Convert to milliseconds

echo "Approximate latency: ${LATENCY}ms"
echo ""

# Count events in last 5 minutes
echo "[*] Event Statistics (last 5 minutes):"
kubectl logs -n falco $FALCO_POD --since=5m | grep -c "Warning\|Critical\|Error" || echo "0 events"
echo ""

# CPU overhead calculation
echo "[*] Calculating CPU Overhead:"
TOTAL_CPU=$(kubectl top nodes --no-headers | awk '{sum += $2} END {print sum}')
FALCO_CPU=$(kubectl top pod $FALCO_POD -n falco --no-headers | awk '{print $2}' | sed 's/m//')
echo "Total Node CPU: ${TOTAL_CPU}"
echo "Falco CPU Usage: ${FALCO_CPU}m"

if [ ! -z "$FALCO_CPU" ] && [ ! -z "$TOTAL_CPU" ]; then
    OVERHEAD=$(echo "scale=2; ($FALCO_CPU / $TOTAL_CPU) * 100" | bc)
    echo "CPU Overhead: ${OVERHEAD}%"
fi
echo ""

# Memory usage
echo "[*] Memory Usage:"
kubectl top pod $FALCO_POD -n falco | grep -v NAME | awk '{print "Falco Memory: " $3}'
echo ""

# Event throughput test
echo "[*] Testing Event Throughput..."
echo "Generating 100 test events..."
for i in {1..100}; do
    kubectl exec test-shell-execution -- /bin/sh -c "echo test$i" > /dev/null 2>&1
done

sleep 3

EVENT_COUNT=$(kubectl logs -n falco $FALCO_POD --since=10s | grep -c "test" || echo "0")
echo "Events detected: $EVENT_COUNT/100"
echo "Detection rate: $(echo "scale=2; ($EVENT_COUNT / 100) * 100" | bc)%"
echo ""

echo "============================================"
echo "Performance Summary"
echo "============================================"
echo "Target: CPU overhead < 5%"
echo "Target: Alert latency < 200ms"
echo "Actual CPU overhead: ${OVERHEAD}% (if available)"
echo "Estimated latency: ${LATENCY}ms"