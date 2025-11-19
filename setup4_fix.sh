#!/bin/bash

set -e

echo "============================================"
echo "Complete Falco Cleanup & Reinstall"
echo "============================================"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# AGGRESSIVE CLEANUP
echo "Step 1: Complete cleanup of all Falco resources..."
echo ""

# Uninstall helm releases
echo "  Removing Helm releases..."
helm uninstall falco -n falco 2>/dev/null && echo "    - Removed falco" || echo "    - falco not found"
helm uninstall falco-exporter -n falco 2>/dev/null && echo "    - Removed falco-exporter" || echo "    - falco-exporter not found"

# Delete all resources in falco namespace
echo "  Deleting all resources in falco namespace..."
kubectl delete daemonset -n falco --all 2>/dev/null || true
kubectl delete deployment -n falco --all 2>/dev/null || true
kubectl delete service -n falco --all 2>/dev/null || true
kubectl delete configmap -n falco --all 2>/dev/null || true
kubectl delete secret -n falco --all 2>/dev/null || true
kubectl delete serviceaccount -n falco --all 2>/dev/null || true
kubectl delete servicemonitor -n falco --all 2>/dev/null || true
kubectl delete pods -n falco --all --force --grace-period=0 2>/dev/null || true

echo "  Waiting for cleanup to complete..."
sleep 15

# Verify namespace is clean
REMAINING=$(kubectl get all -n falco --no-headers 2>/dev/null | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    print_status "Namespace is clean"
else
    print_warning "Some resources still exist (will be overwritten)"
    kubectl get all -n falco
fi
echo ""

# Install Falco with simplified configuration
echo "Step 2: Installing Falco with fixed configuration..."

helm install falco falcosecurity/falco \
    --namespace falco \
    --set driver.kind=modern_ebpf \
    --set tty=true \
    --set falco.grpc.enabled=true \
    --set falco.grpc_output.enabled=true \
    --set falco.json_output=true \
    --set metrics.enabled=true \
    --set falcosidekick.enabled=true \
    --set falcosidekick.ui.enabled=true \
    --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/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" \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=256Mi \
    --set resources.limits.cpu=500m \
    --set resources.limits.memory=512Mi \
    --wait --timeout 5m

print_status "Falco installed"
echo ""

# Wait for pods to be ready
echo "Step 3: Waiting for Falco pods..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=falco \
    -n falco \
    --timeout=180s || {
        echo "Checking pod status:"
        kubectl get pods -n falco
        echo ""
        echo "Checking logs:"
        kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30
        exit 1
    }

print_status "Falco is running!"
kubectl get pods -n falco
echo ""

# Check for errors
echo "Step 4: Verifying Falco configuration..."
sleep 5
ERROR_COUNT=$(kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "error" | grep -v "no error" | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    print_status "No errors in Falco logs"
else
    print_warning "Found $ERROR_COUNT error messages (check if critical):"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep -i "error"
fi
echo ""

# Install Falco Exporter
echo "Step 5: Installing Falco Exporter..."

helm install falco-exporter falcosecurity/falco-exporter \
    --namespace falco \
    --set serviceMonitor.enabled=true \
    --set service.type=ClusterIP \
    --set service.port=9376 \
    --set resources.requests.cpu=50m \
    --set resources.requests.memory=64Mi \
    --wait --timeout 3m

print_status "Falco Exporter installed"
echo ""

# Final status
echo "Step 6: Final status check..."
kubectl get pods -n falco
kubectl get svc -n falco
echo ""

# Create test pod
echo "Step 7: Creating test pod..."
kubectl delete pod test-shell-execution 2>/dev/null || true
sleep 2

kubectl run test-shell-execution \
    --image=alpine:3.18 \
    --labels="app=security-test" \
    --command -- sh -c "while true; do sleep 30; done"

kubectl wait --for=condition=ready pod/test-shell-execution --timeout=60s
print_status "Test pod ready"
echo ""

# Generate events
echo "Step 8: Generating test events..."
sleep 10

for i in {1..3}; do
    echo "  Event batch $i..."
    kubectl exec test-shell-execution -- whoami 2>/dev/null || true
    kubectl exec test-shell-execution -- cat /etc/passwd 2>/dev/null || true
    kubectl exec test-shell-execution -- ls -la 2>/dev/null || true
    sleep 3
done

print_status "Events generated"
echo ""

# Check detections
echo "Step 9: Checking Falco detections..."
sleep 3
EVENTS=$(kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "priority" | wc -l)
if [ "$EVENTS" -gt 0 ]; then
    print_status "Falco detected $EVENTS security events!"
    echo "Sample events:"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5 | grep "priority"
else
    print_warning "No events detected yet. Generate more:"
    echo "  kubectl exec test-shell-execution -- sh -c 'for i in 1 2 3; do whoami; sleep 1; done'"
fi
echo ""

# Check metrics
echo "Step 10: Verifying metrics endpoint..."
EXPORTER_POD=$(kubectl get pod -n falco -l app.kubernetes.io/name=falco-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$EXPORTER_POD" ]; then
    kubectl port-forward -n falco $EXPORTER_POD 9376:9376 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 5
    
    METRICS=$(curl -s http://localhost:9376/metrics 2>/dev/null | grep "falco_events" | wc -l)
    if [ "$METRICS" -gt 0 ]; then
        print_status "Metrics are being exposed!"
        curl -s http://localhost:9376/metrics 2>/dev/null | grep "falco_events" | head -3
    else
        print_warning "Metrics endpoint active but no data yet"
    fi
    
    kill $PF_PID 2>/dev/null || true
fi
echo ""

# Summary
echo "============================================"
echo " Installation Complete!"
echo "============================================"
echo ""
echo "Current status:"
kubectl get pods -n falco
echo ""
echo " Next Steps:"
echo ""
echo "1. Wait 60 seconds for Prometheus to scrape:"
echo "   sleep 60"
echo ""
echo "2. Check Prometheus has the metrics:"
echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &"
echo "   # Open: http://localhost:9090"
echo "   # Query: falco_events"
echo ""
echo "3. Refresh Grafana dashboard:"
echo "   - Time range: Last 6 hours"
echo "   - Click refresh button"
echo "   - You should now see data!"
echo ""
echo "4. If panel still shows 'No data', edit it and try:"
echo "   Query: sum(increase(falco_events[5m]))"
echo ""
echo " Useful commands:"
echo "  Watch Falco events:  kubectl logs -n falco -l app.kubernetes.io/name=falco -f"
echo "  Generate events:     kubectl exec test-shell-execution -- whoami"
echo "  Check metrics:       kubectl port-forward -n falco svc/falco-exporter 9376:9376"
echo ""
echo "check falco_events on prometheus to verify metrics are being collected."


print_status "Setup complete!"

