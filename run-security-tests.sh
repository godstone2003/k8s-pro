#!/bin/bash

echo "============================================"
echo "Falco Security Detection Tests"
echo "============================================"
echo ""

# Deploy test pods
echo "[*] Deploying test pods..."
kubectl apply -f attack-simulations.yaml
sleep 10

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=security-test --timeout=60s

echo ""
echo "============================================"
echo "Test 1: Shell Execution Detection"
echo "============================================"
kubectl exec test-shell-execution -- /bin/sh -c "whoami"
kubectl exec test-shell-execution -- /bin/bash -c "ls -la" 2>/dev/null || echo "Bash not available"
sleep 2

echo ""
echo "============================================"
echo "Test 2: Sensitive File Access Detection"
echo "============================================"
kubectl exec test-file-access -- cat /etc/shadow 2>/dev/null || echo "Shadow file protected (expected)"
kubectl exec test-file-access -- cat /etc/passwd
sleep 2

echo ""
echo "============================================"
echo "Test 3: Privilege Escalation Attempt"
echo "============================================"
kubectl exec test-shell-execution -- su - root 2>/dev/null || echo "Privilege escalation blocked (expected)"
kubectl exec test-privileged -- id
sleep 2

echo ""
echo "============================================"
echo "Test 4: Network Reconnaissance"
echo "============================================"
kubectl exec test-network-tools -- nmap -sn 10.0.0.0/24 2>/dev/null || echo "Nmap test completed"
kubectl exec test-network-tools -- netstat -tulpn
sleep 2

echo ""
echo "============================================"
echo "Test 5: Package Manager Execution"
echo "============================================"
kubectl exec test-shell-execution -- apk update
sleep 2

echo ""
echo "============================================"
echo "Test 6: Suspicious Process Spawning"
echo "============================================"
kubectl exec test-network-tools -- nc -l 1234 &
sleep 2
kubectl exec test-network-tools -- pkill nc

echo ""
echo "============================================"
echo "Tests Completed!"
echo "============================================"
echo ""
echo "Check Falco logs with:"
echo "kubectl logs -n falco -l app.kubernetes.io/name=falco"
echo ""
echo "Check Grafana dashboard at: http://localhost:3000"
echo ""
echo "To clean up test pods:"
echo "kubectl delete -f attack-simulations.yaml"