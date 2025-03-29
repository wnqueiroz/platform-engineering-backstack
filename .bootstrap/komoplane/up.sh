#!/bin/bash

set -euo pipefail

# Change to platform cluster only if needed
if [[ "$(kubectl config current-context)" != "kind-platform" ]]; then
    kubectl config use-context kind-platform || {
        echo "Failed to switch context to kind-platform"
        exit 1
    }
fi

NS=komoplane-system
PORT=8090

echo "Adding Komodorio Helm repository..."
helm repo add komodorio https://helm-charts.komodor.io 2>/dev/null || true
helm repo update

# Create namespace if it does not exist
if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
    echo "Creating namespace: $NS"
    kubectl create namespace "$NS"
else
    echo "Namespace $NS already exists."
fi

echo "Installing or upgrading Komoplane..."
helm upgrade --install komoplane \
    --namespace "$NS" \
    --create-namespace komodorio/komoplane

# Wait for Komoplane to be ready
echo "Waiting for Komoplane deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/komoplane -n "$NS" || {
    echo "Komoplane deployment is not ready"
    exit 1
}

# Background port-forward only if not already running
if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
    if kubectl get svc/komoplane -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for Komoplane on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/komoplane $PORT:$PORT >/dev/null 2>&1 &
        echo "Port-forward started in background."
    else
        echo "Komoplane service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

echo "✅ Komoplane setup completed successfully!"
