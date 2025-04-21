#!/bin/bash

set -euo pipefail

# Switch to the platform cluster if not already set
if [[ "$(kubectl config current-context)" != "kind-platform" ]]; then
    kubectl config use-context kind-platform || {
        echo "Failed to switch context"
        exit 1
    }
fi

NS=argocd-system
BASE_DIR=./argocd
MANIFESTS_DIR="$BASE_DIR/manifests"
PORT=8080
ARGO_PWD_NEW="12345678"
REPO_URL="git@github.com:wnqueiroz/platform-engineering-backstack.git"

echo "Adding Argo CD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

echo "Installing or upgrading Argo CD..."
helm upgrade --install argocd \
    --namespace "$NS" \
    --create-namespace argo/argo-cd

echo "Waiting for Argo CD deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/argocd-server -n "$NS" || {
    echo "Argo CD deployment is not ready"
    exit 1
}

# Start port-forward only if not already active
if ! lsof -i TCP:$PORT >/dev/null 2>&1; then
    if kubectl get svc/argocd-server -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for Argo CD on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/argocd-server $PORT:443 >/dev/null 2>&1 &
    else
        echo "Argo CD service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

# Wait briefly for port-forward to establish
sleep 5

# Get the initial admin password from the secret
INITIAL_PASSWORD=$(kubectl -n "$NS" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "Attempting Argo CD login..."
if argocd login localhost:$PORT --username admin --password "$INITIAL_PASSWORD" --insecure >/dev/null 2>&1; then
    echo "Logged in using initial password."
    echo "Updating Argo CD admin password..."
    argocd account update-password --account admin --current-password "$INITIAL_PASSWORD" --new-password "$ARGO_PWD_NEW"
elif argocd login localhost:$PORT --username admin --password "$ARGO_PWD_NEW" --insecure >/dev/null 2>&1; then
    echo "Already using the updated password. Login succeeded."
else
    echo "Failed to login with both initial and updated password. Aborting."
    exit 1
fi

# Add repo if not already added
if ! argocd repo list | grep -q "$REPO_URL"; then
    echo "Adding Git repo to Argo CD..."
    argocd repo add "$REPO_URL" --ssh-private-key-path ~/.ssh/id_ed25519
else
    echo "Git repo already added."
fi

# Register cluster if not already registered
if ! argocd cluster list | grep -q "kind-platform"; then
    echo "Registering kind-platform cluster to Argo CD..."
    argocd cluster add kind-platform --insecure --in-cluster -y
else
    echo "Cluster kind-platform already registered."
fi

# Apply Argo CD applications or configs
echo "Applying Argo CD manifests..."
kubectl apply -f "$BASE_DIR/crossplane-claims.yaml"

echo "✅ Argo CD setup completed successfully!"
