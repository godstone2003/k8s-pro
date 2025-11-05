#!/bin/bash

# Deploy Prometheus Stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus with Falco ServiceMonitor
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Deploy Falco Exporter for Prometheus metrics
helm install falco-exporter falcosecurity/falco-exporter \
  --namespace falco \
  --set serviceMonitor.enabled=true

# Wait for pods to be ready
echo "Waiting for monitoring stack to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus \
  -n monitoring --timeout=300s

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret --namespace monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)

echo "============================================"
echo "Monitoring Stack Deployed Successfully!"
echo "============================================"
echo "Grafana URL: http://localhost:3000"
echo "Username: admin"
echo "Password: $GRAFANA_PASSWORD"
echo ""
echo "To access Grafana, run:"
echo "kubectl port-forward -n monitoring svc/prometheus-grafana --address 0.0.0.0 3000:80"
echo ""
echo "Prometheus URL: http://localhost:9090"
echo "To access Prometheus, run:"
echo "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus --address 0.0.0.0 9090:9090"