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
