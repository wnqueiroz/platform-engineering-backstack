#!/bin/bash

set -euo pipefail

# Change to platform cluster
if [[ "$(kubectl config current-context)" != "kind-platform" ]]; then
    kubectl config use-context kind-platform || {
        echo "Failed to switch context to kind-platform"
        exit 1
    }
fi

NS=crossplane-system
BASE_DIR=./crossplane
MANIFESTS_DIR="$(dirname "$0")/manifests"
REQUIRED_PROVIDERS=("provider-kubernetes" "provider-aws-sqs")
TIMEOUT=600
INTERVAL=5
ELAPSED=0

echo "Adding Crossplane Helm repository..."
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo update

echo "Installing or upgrading Crossplane..."
helm upgrade --install crossplane \
    --namespace "$NS" \
    --create-namespace crossplane-stable/crossplane

echo "Waiting for Crossplane to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment -n "$NS" -l app.kubernetes.io/name=crossplane

# TODO: remove this later. The Argo CD must be sync this
echo "Applying AWS providers..."
kubectl apply -f "$BASE_DIR/providers" --recursive --namespace "$NS"

echo "Ensuring AWS (LocalStack) secret exists..."
if kubectl get secret aws-secret -n "$NS" >/dev/null 2>&1; then
    echo "AWS secret already exists. Skipping creation."
else
    kubectl create secret generic aws-secret -n "$NS" \
        --from-file=creds="$MANIFESTS_DIR/aws-credentials.txt"
fi

# Function to check if all required providers are healthy
check_providers_health() {
    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        health_status=$(kubectl get providerrevisions.pkg.crossplane.io | grep "$provider" | awk '{print $2}')
        if [ "$health_status" != "True" ]; then
            echo "Provider $provider is not healthy yet. Waiting..."
            return 1
        fi
    done
    return 0
}

echo "Checking provider health status..."
while ! check_providers_health; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "Timeout reached. Some providers did not become healthy in time."
        exit 1
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "All providers are healthy!"
echo "✅ Crossplane setup completed successfully!"
