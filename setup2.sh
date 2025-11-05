#!/bin/bash
set -e

#install helm
echo "==== Installing Helm ===="
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
echo "==== Helm Installed ===="

#install helm
helm install falco-sidekick falcosecurity/falco-sidekick \
  --namespace falco \
  -f falco-sidekick-values.yaml
echo "==== Falco Sidekick Installed ===="  
  
# Add Falco Helm repository
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
echo "==== Falco Helm Repo Added ===="

# Install Falco with eBPF driver
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=ebpf \
  --set tty=true \
  --set falco.grpc.enabled=true \
  --set falco.grpcOutput.enabled=true
echo "==== Falco Installed ===="

# Create ConfigMap with custom rules
kubectl create configmap falco-custom-rules \
  --from-file=custom_rules.yaml=custom_rules.yaml \
  -n falco  

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set customRules."custom-rules\.yaml"="$(cat custom_rules.yaml | base64 -w0)"
echo "==== Custom Rules ConfigMap Created and Applied ===="
