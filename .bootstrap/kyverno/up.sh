#!/bin/bash

set -euo pipefail

# Change to platform cluster
if [[ "$(kubectl config current-context)" != "kind-platform" ]]; then
    kubectl config use-context kind-platform || {
        echo "Failed to switch context to kind-platform"
        exit 1
    }
fi

NS=kyverno-system
POLICIES_DIR=./kyverno
TIMEOUT=240
INTERVAL=5
ELAPSED=0

echo "Waiting for Kyverno webhook to be ready..."
kubectl wait deployment/kyverno-admission-controller \
    -n "$NS" \
    --for=condition=Available=True \
    --timeout=${TIMEOUT}s

echo "Ensuring all Kyverno pods are ready..."
while true; do
    READY=$(kubectl get pods -n "$NS" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | tr " " "\n" | grep -c false || true)
    if [[ "$READY" -eq 0 ]]; then
        break
    fi
    if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
        echo "Timeout reached. Kyverno pods are not ready."
        exit 1
    fi
    echo "Waiting for Kyverno pods to become ready..."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "All Kyverno pods are ready!"

apply_kyverno_policies() {
    local retries=20
    local delay=3

    for i in $(seq 1 $retries); do
        if kubectl apply -f "$POLICIES_DIR" --recursive; then
            echo "✅ Kyverno policies applied successfully!"
            return 0
        else
            echo "⚠️ Failed to apply policies, retrying in ${delay}s... (${i}/${retries})"
            sleep $delay
        fi
    done

    echo "❌ Failed to apply Kyverno policies after ${retries} attempts."
    exit 1
}

echo "Applying Kyverno policies from $POLICIES_DIR..."
apply_kyverno_policies

echo "✅ Kyverno setup and policy application completed successfully!"
