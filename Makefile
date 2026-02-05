
.PHONY: up down check_bins

check_bins:
	@command -v kind >/dev/null 2>&1 || { echo >&2 "kind not found! Please install it before continuing."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl not found! Please install it before continuing."; exit 1; }
	@command -v argocd >/dev/null 2>&1 || { echo >&2 "argocd not found! Please install it before continuing."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo >&2 "helm not found! Please install it before continuing."; exit 1; }
	@command -v yq >/dev/null 2>&1 || { echo >&2 "yq not found! Please install it before continuing."; exit 1; }
	@YQ_VERSION=$$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -n "$$YQ_VERSION" ]; then \
		YQ_MAJOR=$$(echo $$YQ_VERSION | cut -d. -f1); \
		YQ_MINOR=$$(echo $$YQ_VERSION | cut -d. -f2); \
		YQ_PATCH=$$(echo $$YQ_VERSION | cut -d. -f3); \
		if [ $$YQ_MAJOR -lt 4 ] || ([ $$YQ_MAJOR -eq 4 ] && [ $$YQ_MINOR -lt 45 ]) || ([ $$YQ_MAJOR -eq 4 ] && [ $$YQ_MINOR -eq 45 ] && [ $$YQ_PATCH -lt 1 ]); then \
			echo >&2 "yq version $$YQ_VERSION is too old! Please install version v4.45.1 or higher."; \
			exit 1; \
		fi; \
	else \
		echo >&2 "Could not determine yq version! Please ensure yq v4.45.1 or higher is installed."; \
		exit 1; \
	fi

up: check_bins
	@echo "Creating environment..."
	@if kind get clusters | grep -q "^platform$$"; then \
		echo "Cluster 'platform' already exists. Skipping..."; \
	else \
		kind create cluster --name platform; \
	fi

	@./.bootstrap/argocd/up.sh
	@./.bootstrap/backstage/up.sh
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
