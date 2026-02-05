#!/bin/bash

set -euo pipefail

# Configuration
NS=crossview-system
BASE_DIR="$(dirname "$0")"
PORT=3001
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

# Wait for postgres deployment to exist (ArgoCD needs time to create it)
echo "Waiting for postgres deployment to be created..."
TIMEOUT=120
ELAPSED=0
while ! kubectl get deployment crossview-postgres -n "$NS" >/dev/null 2>&1; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for postgres deployment to be created"
        echo "Hint: Make sure you've committed and pushed the manifests to Git, or use 'make crossview-up' for local testing"
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for postgres deployment to be ready
echo "Waiting for postgres deployment to be ready..."
kubectl rollout status deployment/crossview-postgres -n "$NS" --timeout=120s || {
    echo "❌ Postgres deployment is not ready"
    exit 1
}

# Wait for crossview deployment to exist
echo "Waiting for crossview deployment to be created..."
ELAPSED=0
while ! kubectl get deployment crossview -n "$NS" >/dev/null 2>&1; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for crossview deployment to be created"
        echo "Hint: Make sure you've committed and pushed the manifests to Git, or use 'make crossview-up' for local testing"
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for crossview deployment to be ready
echo "Waiting for crossview deployment to be ready..."
kubectl rollout status deployment/crossview -n "$NS" --timeout=120s || {
    echo "❌ Crossview deployment is not ready"
    exit 1
}

# Start port-forward in background if not already running
if ! lsof -i TCP:$PORT | grep LISTEN >/dev/null 2>&1; then
    if kubectl get svc/crossview -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for Crossview on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/crossview ${PORT}:3001 >/dev/null 2>&1 &
        echo "Port-forward started in background."
    else
        echo "Crossview service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

echo "✅ Crossview setup completed successfully!"
