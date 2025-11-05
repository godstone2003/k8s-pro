#!/bin/bash

# Install Falco Sidekick
helm install falco-sidekick falcosecurity/falcosidekick \
  --namespace falco \
  -f falco-sidekick-values.yaml

# Verify deployment
kubectl get pods -n falco