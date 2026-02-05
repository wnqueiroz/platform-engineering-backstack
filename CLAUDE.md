# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Platform Engineering BACK Stack** - a local development environment combining (B)ackstage, (A)rgoCD, (C)rossplane, and (K)yverno to create an Internal Developer Platform (IDP). The stack runs on a local Kubernetes cluster (kind) and demonstrates GitOps patterns, infrastructure abstraction, and policy enforcement.

## Architecture

### High-Level Flow

1. **Backstage** provides developer portal with self-service templates
2. **Scaffolder templates** create PRs with Crossplane claims
3. **GitHub Actions** validate claims against Kyverno policies
4. **ArgoCD** syncs approved claims from Git to Kubernetes cluster
5. **Crossplane** provisions infrastructure (AWS SQS queues via LocalStack)
6. **Kyverno** enforces policies at admission time

### Key Patterns

- **GitOps**: All infrastructure definitions in Git, ArgoCD syncs to cluster
- **App of Apps**: ArgoCD `apps.yaml` references individual app definitions in `/argocd/apps/`
- **Infrastructure Abstraction**: Crossplane XRDs define platform APIs, Compositions implement them
- **Policy as Code**: Kyverno policies validate both in CI (pre-merge) and admission control (runtime)

### Directory Structure

```
/
├── .bootstrap/          # Shell scripts that initialize each component in the cluster
│   ├── argocd/         # Installs ArgoCD, configures repo, applies apps
│   ├── backstage/      # Deploys Backstage to cluster
│   ├── crossplane/     # Installs Crossplane, providers, and provider configs
│   ├── komoplane/      # Deploys Crossplane visualization tool
│   ├── kyverno/        # Installs Kyverno policy engine
│   └── localstack/     # Deploys LocalStack for AWS emulation
├── argocd/
│   ├── apps.yaml       # App of Apps - references all applications
│   ├── apps/           # Individual ArgoCD Application definitions
│   └── crossplane-system.yaml
├── crossplane/
│   ├── xrds/           # CompositeResourceDefinitions (platform APIs)
│   ├── compositions/   # Implementations of XRDs (e.g., AWS SQS)
│   ├── claims/         # Actual infrastructure requests from users
│   ├── providers/      # Crossplane provider installations
│   └── providers-config/ # Provider authentication configs
├── kyverno/            # ClusterPolicy definitions
├── backstage/          # Backstage monorepo
│   ├── packages/       # app/ and backend/
│   ├── catalog/        # Service catalog and templates
│   ├── app-config.yaml # Main Backstage configuration
│   └── Makefile        # Helper commands
└── api-server/         # Example Go app for creating Crossplane claims

```

## Common Commands

### Environment Setup

```bash
# From repository root
make up              # Create kind cluster, bootstrap all components
make down            # Delete kind cluster
make setup-local-config  # Update Backstage app-config.local.yaml with cluster credentials
```

### Backstage Development

```bash
# From /backstage directory
yarn install         # Install dependencies
yarn start           # Start dev server (frontend + backend)
yarn build:backend   # Build backend only
yarn build-image     # Build Docker image
yarn lint            # Lint code (checks since origin/main)
yarn lint:all        # Lint all code
yarn test            # Run tests
yarn test:all        # Run tests with coverage
yarn test:e2e        # Run Playwright e2e tests
yarn prettier:check  # Check formatting
```

### Backstage Local Development

The Backstage instance requires specific environment configuration:

- Create `.env` file in root with `GITHUB_TOKEN` (for catalog ingestion and PR creation)
- After running `make up`, run `make setup-local-config` to generate `backstage/app-config.local.yaml` with cluster credentials
- Start Backstage with `cd backstage && yarn start`
- Access at http://localhost:3000 (login as Guest)

### Working with Crossplane

```bash
# View Crossplane resources
kubectl get xrd                           # View XRDs (API definitions)
kubectl get composition                   # View Compositions (implementations)
kubectl get xqueueclaim -A               # View claims (user requests)
kubectl get queue.sqs.aws.upbound.io -A  # View actual AWS resources

# Debug Crossplane issues
kubectl describe xqueueclaim <name> -n <namespace>  # Check claim status
kubectl logs -n crossplane-system deployment/crossplane  # Check Crossplane logs
```

### Working with ArgoCD

```bash
# ArgoCD is accessible at http://localhost:8080
# Username: admin, Password: 12345678

argocd app list                    # List all applications
argocd app get <app-name>          # Get app details
argocd app sync <app-name>         # Manually sync app
argocd app diff <app-name>         # Show differences
```

### Working with Kyverno

```bash
# Validate policies locally against claims
kyverno apply ./kyverno --resource ./crossplane/claims

# View policies in cluster
kubectl get clusterpolicy
kubectl describe clusterpolicy validate-xqueue-fields
```

## Development Workflows

### Adding a New Crossplane Claim

1. **Via Backstage Template** (Recommended):
   - Navigate to http://localhost:3000/create
   - Use "Create XQueue Claim" template
   - Fill in form → creates PR automatically

2. **Manually**:
   - Create YAML in `/crossplane/claims/<name>.yaml`
   - Validate locally: `kyverno apply ./kyverno --resource ./crossplane/claims`
   - Create PR → GitHub Actions validates → Merge → ArgoCD syncs

### Creating a New Crossplane XRD

1. Define XRD in `/crossplane/xrds/<name>.yaml`
2. Create Composition in `/crossplane/compositions/<provider>/<name>.yaml`
3. Create Backstage template in `/backstage/catalog/templates/<name>/template.yaml`
4. Add Kyverno policy in `/kyverno/validate-<name>-fields.yaml`
5. Update ArgoCD to watch new resource (if needed)

### Modifying Bootstrap Process

The `.bootstrap/*/up.sh` scripts handle component installation. When modifying:

- Each script is idempotent (safe to run multiple times)
- Scripts check if resources exist before creating
- Follow existing patterns: install → wait for ready → configure → apply manifests

### Working with Backstage Templates

Templates are located in `/backstage/catalog/templates/`. Each template:

- Uses `fetch:template` to render skeleton files
- Uses `publish:github:pull-request` to create PR
- Targets `/crossplane/claims` path in the repository

## Important Considerations

### Git Repository Configuration

- The ArgoCD bootstrap script hardcodes the repository URL and expects SSH authentication
- When forking: Update `REPO_URL` in `.bootstrap/argocd/up.sh` to your fork
- Ensure SSH key (`~/.ssh/id_ed25519`) has access to the repository
- Backstage templates also reference the repository owner/name in template definitions

### Provider Configuration

- Crossplane providers use LocalStack by default (`default` provider config)
- LocalStack endpoint: http://localstack.localstack-system.svc.cluster.local:4566
- LocalStack credentials are dummy values (test/test) per AWS local development standards
- To use real AWS: create new provider config, update compositions to reference it

### Policy Validation

Kyverno policies are enforced in two places:

1. **CI Pipeline** (`.github/workflows/validate-claims.yaml`): Validates claims before merge
2. **Admission Control**: Kyverno runs in-cluster and blocks invalid resources

Ensure both are kept in sync. If you modify XRD schemas, update corresponding Kyverno policies.

### Namespace Conventions

- ArgoCD: `argocd-system`
- Backstage: `backstage-system`
- Crossplane: `crossplane-system`
- Kyverno: `kyverno-system`
- LocalStack: `localstack-system`
- Claims: deployed in namespace specified in claim YAML (e.g., `default`)

## Testing

### Testing Backstage Templates Locally

```bash
cd backstage
yarn start
# Navigate to http://localhost:3000/create
# Test template end-to-end (creates real PR to repo)
```

### Testing Kyverno Policies

```bash
# Test against all claims
kyverno apply ./kyverno --resource ./crossplane/claims

# Test against specific claim
kyverno apply ./kyverno --resource ./crossplane/claims/my-claim.yaml
```

### Testing Crossplane Compositions

1. Create a test claim YAML
2. Apply to cluster: `kubectl apply -f test-claim.yaml`
3. Watch resources: `kubectl get xqueue,queue -A --watch`
4. Check events: `kubectl describe xqueueclaim <name> -n <namespace>`

## Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat(scope): description` - New feature
- `fix(scope): description` - Bug fix
- `docs(scope): description` - Documentation changes
- `chore(scope): description` - Maintenance tasks

Examples:

- `feat(xrd): add NoSQL database XRD`
- `fix(backstage): correct template validation`
- `chore(argocd): update targetRevision to HEAD`
- `docs(readme): update setup instructions`

## Troubleshooting

### Backstage not connecting to Kubernetes

- Run `make setup-local-config` to regenerate credentials
- Check `backstage/app-config.local.yaml` has valid token and cluster URL
- Verify service account exists: `kubectl get sa backstage -n backstage-system`

### Crossplane resources stuck in "Creating"

- Check provider logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-sqs`
- Verify provider config: `kubectl get providerconfig default -o yaml`
- Check LocalStack is running: `kubectl get pod -n localstack-system`

### ArgoCD not syncing

- Check application status: `argocd app get <app-name>`
- Verify Git repository is accessible: `argocd repo list`
- Check ArgoCD server logs: `kubectl logs -n argocd-system deployment/argocd-server`

### Kyverno policies blocking valid resources

- Review policy: `kubectl get clusterpolicy validate-xqueue-fields -o yaml`
- Check admission webhook: `kubectl get validatingwebhookconfigurations | grep kyverno`
- Temporarily disable policy: `kubectl delete clusterpolicy validate-xqueue-fields`
