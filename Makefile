# =========================
# VectorFlow Root Makefile
# =========================
# Orchestrates builds across all services

.PHONY: all build test clean dev setup help
.PHONY: build-go build-rust build-python build-frontend
.PHONY: test-go test-rust test-python test-frontend
.PHONY: docker-build docker-push docker-up docker-down
.PHONY: k8s-deploy k8s-delete k8s-status
.PHONY: lint lint-go lint-rust lint-python lint-frontend
.PHONY: chef-lint chef-test chef-converge chef-compliance
.PHONY: cli-install cli-search cli-health cli-status
.PHONY: minikube-start minikube-stop minikube-delete minikube-dashboard
.PHONY: cleanup cleanup-local cleanup-aws
.PHONY: tf-init tf-plan tf-apply tf-destroy tf-fmt
.PHONY: test-integration test-integration-setup
.PHONY: helm-lint helm-template helm-install helm-upgrade helm-uninstall helm-package

# Default target
.DEFAULT_GOAL := help

# ===== Variables =====
DOCKER_REGISTRY ?= localhost:5000
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT_SHA ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Service directories
GO_DIR := go
RUST_DIR := rust
PYTHON_DIR := python
FRONTEND_DIR := frontend

# ===== Help =====
help: ## Show this help message
	@echo "VectorFlow - Enterprise Semantic Search Platform"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ===== Setup =====
setup: ## Initial project setup (run once)
	@echo "Setting up VectorFlow development environment..."
	@./scripts/setup.sh

dev-setup: ## Setup development environment with hot-reload
	@echo "Setting up development environment..."
	@./scripts/dev-setup.sh

# ===== Build Commands =====
all: build ## Build all services

build: build-go build-rust build-python build-frontend ## Build all services
	@echo "All services built successfully!"

build-go: ## Build Go gateway service
	@echo "Building Go gateway..."
	@cd $(GO_DIR) && $(MAKE) build

build-rust: ## Build Rust worker service
	@echo "Building Rust worker..."
	@cd $(RUST_DIR) && $(MAKE) build

build-python: ## Build Python inference service
	@echo "Building Python inference service..."
	@cd $(PYTHON_DIR) && $(MAKE) build

build-frontend: ## Build Next.js frontend
	@echo "Building Next.js frontend..."
	@cd $(FRONTEND_DIR) && npm run build

# ===== Test Commands =====
test: test-go test-rust test-python test-frontend ## Run all tests
	@echo "All tests passed!"

test-go: ## Run Go tests
	@echo "Testing Go gateway..."
	@cd $(GO_DIR) && $(MAKE) test

test-rust: ## Run Rust tests
	@echo "Testing Rust worker..."
	@cd $(RUST_DIR) && $(MAKE) test

test-python: ## Run Python tests
	@echo "Testing Python inference service..."
	@cd $(PYTHON_DIR) && $(MAKE) test

test-frontend: ## Run frontend tests
	@echo "Testing Next.js frontend..."
	@cd $(FRONTEND_DIR) && npm test

# ===== Lint Commands =====
lint: lint-go lint-rust lint-python lint-frontend ## Lint all services
	@echo "All linting passed!"

lint-go: ## Lint Go code
	@cd $(GO_DIR) && $(MAKE) lint

lint-rust: ## Lint Rust code
	@cd $(RUST_DIR) && $(MAKE) lint

lint-python: ## Lint Python code
	@cd $(PYTHON_DIR) && $(MAKE) lint

lint-frontend: ## Lint frontend code
	@cd $(FRONTEND_DIR) && npm run lint

# ===== Docker Commands =====
docker-build: ## Build all Docker images
	@echo "Building Docker images..."
	@docker compose build

docker-push: ## Push all Docker images to registry
	@echo "Pushing Docker images to $(DOCKER_REGISTRY)..."
	@docker compose push

docker-up: ## Start all services with Docker Compose
	@echo "Starting services..."
	@docker compose up -d

docker-down: ## Stop all services
	@echo "Stopping services..."
	@docker compose down

docker-logs: ## Show logs from all services
	@docker compose logs -f

docker-clean: ## Remove all Docker artifacts
	@echo "Cleaning Docker artifacts..."
	@docker compose down -v --rmi local

# ===== Kubernetes Commands =====
k8s-deploy: ## Deploy to Kubernetes cluster
	@echo "Deploying to Kubernetes..."
	@kubectl apply -k k8s/

k8s-delete: ## Delete from Kubernetes cluster
	@echo "Removing from Kubernetes..."
	@kubectl delete -k k8s/

k8s-status: ## Show Kubernetes deployment status
	@echo "Kubernetes Status:"
	@kubectl get pods -n vectorflow
	@kubectl get services -n vectorflow

k8s-logs: ## Show logs from Kubernetes pods
	@kubectl logs -f -l app=vectorflow -n vectorflow

# ===== Development =====
dev: ## Start development environment
	@echo "Starting development environment..."
	@docker compose -f docker-compose.yml -f docker-compose.dev.yml up

run-local: ## Run all services locally (without Docker)
	@echo "Starting local development servers..."
	@./scripts/run-local.sh

# ===== Clean Commands =====
clean: ## Clean all build artifacts
	@echo "Cleaning build artifacts..."
	@cd $(GO_DIR) && $(MAKE) clean 2>/dev/null || true
	@cd $(RUST_DIR) && $(MAKE) clean 2>/dev/null || true
	@cd $(PYTHON_DIR) && $(MAKE) clean 2>/dev/null || true
	@cd $(FRONTEND_DIR) && rm -rf .next node_modules 2>/dev/null || true
	@echo "Clean complete!"

clean-all: clean docker-clean ## Clean everything including Docker
	@echo "Full clean complete!"

# ===== CI/CD Helpers =====
ci-build: lint test build docker-build ## Full CI build pipeline
	@echo "CI build complete!"

ci-deploy: docker-push k8s-deploy ## Deploy pipeline
	@echo "Deployment complete!"

# ===== Version Info =====
version: ## Show version information
	@echo "VectorFlow $(VERSION)"
	@echo "Commit: $(COMMIT_SHA)"

# ===== Chef/Configuration Management =====
CHEF_DIR := chef

chef-lint: ## Lint Chef cookbooks
	@echo "Linting Chef cookbooks..."
	@cd $(CHEF_DIR) && $(MAKE) lint

chef-test: ## Run Chef cookbook tests
	@echo "Running Chef tests..."
	@cd $(CHEF_DIR) && $(MAKE) test

chef-converge: ## Run chef-client in local mode
	@echo "Running Chef converge..."
	@cd $(CHEF_DIR) && $(MAKE) converge

chef-compliance: ## Run InSpec compliance tests
	@echo "Running compliance tests..."
	@cd $(CHEF_DIR) && inspec exec compliance/vectorflow

chef-kitchen: ## Run Test Kitchen integration tests
	@echo "Running Test Kitchen..."
	@cd $(CHEF_DIR) && kitchen test

# ===== Ansible Commands =====
ansible-setup: ## Run Ansible local dev setup
	@echo "Running Ansible local development setup..."
	@cd ansible && ansible-playbook playbooks/local-dev-setup.yml

ansible-deploy: ## Run Ansible VectorFlow deployment
	@echo "Deploying VectorFlow with Ansible..."
	@cd ansible && ansible-playbook playbooks/deploy-vectorflow.yml

# ===== CLI Commands =====
CLI_DIR := cli

cli-install: ## Install CLI in development mode
	@echo "Installing VectorFlow CLI..."
	@cd $(CLI_DIR) && pip install -e .

cli-search: ## Run a quick search (usage: make cli-search QUERY="your query")
	@./scripts/vf search "$(QUERY)"

cli-health: ## Check system health via CLI
	@./scripts/vf-health.sh

cli-status: ## Show detailed system status
	@./scripts/vf status

# ===== Minikube (Local Kubernetes) =====
minikube-start: ## Start Minikube with recommended settings
	@echo "Starting Minikube..."
	@minikube start --cpus=4 --memory=8192 --driver=docker
	@minikube addons enable ingress
	@minikube addons enable metrics-server
	@echo "Minikube started! Run 'eval \$$(minikube docker-env)' to use Minikube's Docker"

minikube-stop: ## Stop Minikube (preserves data)
	@echo "Stopping Minikube..."
	@minikube stop

minikube-delete: ## Delete Minikube cluster (clean slate)
	@echo "Deleting Minikube cluster..."
	@minikube delete

minikube-dashboard: ## Open Minikube dashboard
	@minikube dashboard

minikube-tunnel: ## Start Minikube tunnel for LoadBalancer services
	@echo "Starting Minikube tunnel (requires sudo)..."
	@minikube tunnel

local-dev: docker-up ## Start local development (Docker Compose - zero cloud cost)
	@echo ""
	@echo "VectorFlow is running locally!"
	@echo "  Frontend: http://localhost:3000"
	@echo "  Gateway:  http://localhost:8080"
	@echo "  Worker:   http://localhost:8081"
	@echo "  Inference: http://localhost:8082"
	@echo ""
	@echo "Cost: \$$0.00"

# ===== Cleanup Commands =====
cleanup: ## Full cleanup - AWS resources + local (SAFE - requires confirmation)
	@./scripts/cleanup.sh

cleanup-aws: ## Cleanup AWS resources only
	@echo "Running AWS-only cleanup..."
	@./scripts/cleanup.sh

cleanup-local: ## Cleanup local resources only (Docker, Minikube)
	@echo "Cleaning up local resources..."
	@docker compose down --remove-orphans 2>/dev/null || true
	@minikube delete 2>/dev/null || true
	@docker system prune -f
	@echo "Local cleanup complete!"

cleanup-docker: ## Remove all VectorFlow Docker resources
	@echo "Removing VectorFlow Docker resources..."
	@docker compose down -v --rmi all 2>/dev/null || true
	@docker images --format "{{.Repository}}:{{.Tag}}" | grep vectorflow | xargs -r docker rmi -f 2>/dev/null || true
	@echo "Docker cleanup complete!"

# ===== Terraform (Infrastructure as Code) =====
TERRAFORM_DIR := terraform

tf-init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	@cd $(TERRAFORM_DIR) && terraform init

tf-plan: ## Plan Terraform changes
	@echo "Planning Terraform changes..."
	@cd $(TERRAFORM_DIR) && terraform plan

tf-apply: ## Apply Terraform changes (creates AWS resources)
	@echo "Applying Terraform configuration..."
	@cd $(TERRAFORM_DIR) && terraform apply

tf-destroy: ## Destroy all Terraform-managed AWS resources
	@echo "Destroying Terraform infrastructure..."
	@cd $(TERRAFORM_DIR) && terraform destroy

tf-fmt: ## Format Terraform files
	@cd $(TERRAFORM_DIR) && terraform fmt -recursive

tf-validate: ## Validate Terraform configuration
	@cd $(TERRAFORM_DIR) && terraform validate

tf-output: ## Show Terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

# ===== Integration Tests =====
test-integration-setup: ## Install integration test dependencies
	@echo "Installing integration test dependencies..."
	@pip install -r tests/requirements.txt

test-integration: ## Run integration tests (services must be running)
	@echo "Running integration tests..."
	@echo "Note: Services must be running (use 'make docker-up' first)"
	@pytest tests/integration/ -v --tb=short

test-integration-ci: docker-up ## Run integration tests in CI (starts services first)
	@echo "Waiting for services to start..."
	@sleep 30
	@pytest tests/integration/ -v --tb=short
	@$(MAKE) docker-down

# ===== Helm (Kubernetes Packaging) =====
HELM_CHART := helm/vectorflow
HELM_RELEASE := vectorflow
HELM_NAMESPACE := vectorflow

helm-lint: ## Lint Helm chart
	@echo "Linting Helm chart..."
	@helm lint $(HELM_CHART)

helm-template: ## Render Helm templates locally
	@echo "Rendering Helm templates..."
	@helm template $(HELM_RELEASE) $(HELM_CHART) --namespace $(HELM_NAMESPACE)

helm-install: ## Install Helm chart to cluster
	@echo "Installing VectorFlow Helm chart..."
	@helm install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace

helm-upgrade: ## Upgrade Helm release
	@echo "Upgrading VectorFlow Helm chart..."
	@helm upgrade $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(HELM_NAMESPACE) \
		--install

helm-uninstall: ## Uninstall Helm release
	@echo "Uninstalling VectorFlow Helm chart..."
	@helm uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

helm-package: ## Package Helm chart
	@echo "Packaging Helm chart..."
	@helm package $(HELM_CHART)

helm-dry-run: ## Dry run Helm install
	@echo "Dry run Helm install..."
	@helm install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(HELM_NAMESPACE) \
		--dry-run --debug
