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
BASE_DIR="$(dirname "$0")"
MANIFESTS_DIR="$BASE_DIR/manifests"

# Wait for Komoplane to be ready
echo "Waiting for Komoplane deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/komoplane -n "$NS" || {
    echo "Komoplane deployment is not ready"
    exit 1
}

kubectl patch deploy komoplane -n $NS --patch-file $MANIFESTS_DIR/deployment.yaml
kubectl patch svc komoplane -n $NS --patch-file $MANIFESTS_DIR/service.yaml
kubectl rollout restart deployment komoplane -n $NS
kubectl rollout status deployment komoplane -n $NS

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
