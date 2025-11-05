#!/bin/bash
set -e
set -o pipefail

echo "==== Adding Falco Helm Repo ===="
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

echo "==== Creating namespace 'falco' if not exists ===="
kubectl get ns falco >/dev/null 2>&1 || kubectl create namespace falco


echo "==== Installing Falco with eBPF Driver ===="
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --set driver.kind=ebpf \
  --set tty=true \
  --set falco.grpc.enabled=true \
  --set falco.grpcOutput.enabled=true


echo "==== Installing Falco Sidekick ===="
helm upgrade --install falco-sidekick falcosecurity/falco-sidekick \
  --namespace falco \
  -f falco-sidekick-values.yaml


echo "==== Creating/Updating custom rules ConfigMap ===="
kubectl delete configmap falco-custom-rules -n falco --ignore-not-found=true

kubectl create configmap falco-custom-rules \
  --from-file=custom_rules.yaml=custom_rules.yaml \
  -n falco


echo "==== Injecting custom rules into Falco Helm values ===="
ENCODED_RULES=$(base64 -w0 custom_rules.yaml)

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set customRules."custom-rules\.yaml"="$ENCODED_RULES"


echo "==== Falco Deployment Completed Successfully ===="
kubectl get pods -n falco
