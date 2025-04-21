#!/bin/bash

set -euo pipefail

# Configuration
NS=backstage-system
BASE_DIR="$(dirname "$0")"
MANIFESTS_DIR="$BASE_DIR/manifests"
PORT=8070
IMAGE="backstage:1.0.0"
CLUSTER_NAME="platform"
CONTEXT_NAME="kind-${CLUSTER_NAME}"

# Switch kubectl context if not already set
if [[ "$(kubectl config current-context)" != "$CONTEXT_NAME" ]]; then
    echo "Switching kubectl context to $CONTEXT_NAME..."
    kubectl config use-context "$CONTEXT_NAME" || {
        echo "❌ Failed to switch context to $CONTEXT_NAME"
        exit 1
    }
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
    echo "Creating namespace: $NS"
    kubectl create namespace "$NS"
else
    echo "✅ Namespace $NS already exists."
fi

echo "Building Backstage image $IMAGE..."
cd ./backstage
docker rmi -f $IMAGE
yarn build:all
yarn build-image --tag "$IMAGE" --no-cache
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"
cd ..

# Apply manifests to the cluster (idempotent)
echo "Applying manifests from $MANIFESTS_DIR..."
kubectl apply -f "$MANIFESTS_DIR" --recursive --namespace "$NS"

# Wait for postgres deployment to be ready
echo "Waiting for postgres deployment to be ready..."
kubectl rollout status deployment/postgres -n "$NS" --timeout=120s || {
    echo "❌ Postgres deployment is not ready"
    exit 1
}

# Wait for backstage deployment to be ready
echo "Waiting for backstage deployment to be ready..."
kubectl rollout status deployment/backstage -n "$NS" --timeout=120s || {
    echo "❌ Backstage deployment is not ready"
    exit 1
}

# Start port-forward in background if not already running
if ! lsof -i TCP:$PORT | grep LISTEN >/dev/null 2>&1; then
    if kubectl get svc/backstage -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for Backstage on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/backstage ${PORT}:80 >/dev/null 2>&1 &
        echo "Port-forward started in background."
    else
        echo "Backstage service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

echo "✅ Backstage setup completed successfully!"
