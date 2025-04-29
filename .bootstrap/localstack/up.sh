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
MANIFESTS_DIR="$BASE_DIR/manifests"
NS="localstack-system"

# Wait for LocalStack deployment to be available
echo "Waiting for LocalStack service to be ready..."
kubectl wait --for=condition=available --timeout=240s deployment/localstack -n "$NS" || {
    echo "LocalStack deployment is not ready"
    exit 1
}

# Background port-forward (only if not already running)
PORT=4566
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
