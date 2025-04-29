
.PHONY: up down check_bins

check_bins:
	@command -v kind >/dev/null 2>&1 || { echo >&2 "kind not found! Please install it before continuing."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl not found! Please install it before continuing."; exit 1; }
	@command -v argocd >/dev/null 2>&1 || { echo >&2 "argocd not found! Please install it before continuing."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo >&2 "helm not found! Please install it before continuing."; exit 1; }

up: check_bins
	@echo "Creating environment..."
	@if kind get clusters | grep -q "^platform$$"; then \
		echo "Cluster 'platform' already exists. Skipping..."; \
	else \
		kind create cluster --name platform; \
	fi

	# @./.bootstrap/backstage/up.sh
	@./.bootstrap/argocd/up.sh
	@./.bootstrap/localstack/up.sh
	@./.bootstrap/crossplane/up.sh
	@./.bootstrap/komoplane/up.sh
	@./.bootstrap/kyverno/up.sh

	@make setup-local-config

	@echo
	@echo "---------------------------------------------------------------------------------------------------------------------------"
	@echo "Backstage is accessible at http://localhost:3000"
	@echo "Argo CD is accessible at http://localhost:8080"
	@echo "Komoplane is accessible at http://localhost:8090"
	@echo "LocalStack is accessible at http://localhost:4566 (Manage through the platform at: https://app.localstack.cloud/instances)"

down: check_bins
	@echo "Deleting environment..."
	@if kind get clusters | grep -q "^platform$$"; then \
		kind delete cluster --name platform; \
	else \
		echo "Cluster 'platform' not found. Skipping..."; \
	fi

setup-local-config: check_bins
	@echo "Updating app-config.local.yaml..."
	@test -f backstage/app-config.local.yaml || echo "{}" > backstage/app-config.local.yaml
	@export SERVICE_ACCOUNT_TOKEN=$$(kubectl get secret -n backstage-system backstage-token -o jsonpath='{.data.token}' | base64 --decode); \
	export CLUSTER_URL=$$(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $$NF}'); \
	FILE="backstage/app-config.local.yaml"; \
	yq -i '.kubernetes.clusterLocatorMethods[0].clusters[0].serviceAccountToken = strenv(SERVICE_ACCOUNT_TOKEN)' $$FILE; \
	yq -i '.kubernetes.clusterLocatorMethods[0].clusters[0].url = strenv(CLUSTER_URL)' $$FILE
