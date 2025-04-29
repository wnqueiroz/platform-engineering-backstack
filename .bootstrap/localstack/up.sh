#!/bin/bash

set -euo pipefail

# Change to platform cluster only if needed
if [[ "$(kubectl config current-context)" != "kind-platform" ]]; then
    kubectl config use-context kind-platform || {
        echo "Failed to switch context to kind-platform"
        exit 1
    }
fi

BASE_DIR="$(dirname "$0")"
NS="localstack-system"
PORT=4566

# Create namespace if it does not exist
if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
    echo "Creating namespace: $NS"
    kubectl create namespace "$NS"
else
    echo "Namespace $NS already exists."
fi

# Wait for Deployment to exist
echo "Waiting for LocalStack Deployment to be created..."
for i in {1..24}; do
    if kubectl get deployment/localstack -n "$NS" >/dev/null 2>&1; then
        echo "LocalStack Deployment found."
        break
    fi
    echo "Deployment not found yet. Retrying in 5s..."
    sleep 5
done

# After Deployment exists, wait for it to become available
echo "Waiting for LocalStack Deployment to become available..."
kubectl wait --for=condition=available --timeout=120s deployment/localstack -n "$NS" || {
    echo "LocalStack Deployment is not ready after waiting."
    exit 1
}

# Background port-forward (only if not already running)
if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
    if kubectl get svc/localstack -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for LocalStack on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/localstack ${PORT}:${PORT} >/dev/null 2>&1 &
        echo "Port-forward started in background."
    else
        echo "LocalStack service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

echo "✅ LocalStack setup completed successfully!"
