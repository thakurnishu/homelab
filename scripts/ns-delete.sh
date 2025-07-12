#!/bin/bash

NAMESPACE=$1

if [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

echo "Force deleting namespace: $NAMESPACE"

# Remove finalizers
kubectl get namespace "$NAMESPACE" -o json | \
  jq 'del(.spec.finalizers)' | \
  kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -

echo "Namespace $NAMESPACE force-deletion attempted."
