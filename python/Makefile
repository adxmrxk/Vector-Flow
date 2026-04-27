# =========================
# VectorFlow Inference Service Makefile
# =========================

.PHONY: all install install-dev build test lint format clean run docker-build docker-run help

.DEFAULT_GOAL := help

# Variables
PYTHON := python3
PIP := pip
VENV := venv
DOCKER_IMAGE := vectorflow-inference
DOCKER_TAG := latest

# ----- Help -----
help: ## Show this help message
	@echo "VectorFlow Inference Service"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ----- Setup -----
venv: ## Create virtual environment
	$(PYTHON) -m venv $(VENV)
	@echo "Virtual environment created. Activate with: source $(VENV)/bin/activate"

install: ## Install production dependencies
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

install-dev: ## Install development dependencies
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements-dev.txt
	pre-commit install || true

# ----- Build -----
build: ## Build the package
	$(PIP) install build
	$(PYTHON) -m build

# ----- Development -----
run: ## Run the service locally
	$(PYTHON) -m app.main

run-reload: ## Run with hot-reload
	uvicorn app.api:app --reload --host 0.0.0.0 --port 8082

# ----- Testing -----
test: ## Run tests
	pytest tests/ -v

test-cov: ## Run tests with coverage
	pytest tests/ -v --cov=app --cov=services --cov-report=html --cov-report=term

# ----- Linting -----
lint: ## Run linters
	ruff check app/ services/
	mypy app/ services/

format: ## Format code
	black app/ services/ tests/
	ruff check --fix app/ services/

check: lint test ## Run all checks

# ----- Docker -----
docker-build: ## Build Docker image
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

docker-run: ## Run Docker container
	docker run -p 8082:8082 \
		-e ENVIRONMENT=development \
		-v $(PWD)/models:/app/models \
		$(DOCKER_IMAGE):$(DOCKER_TAG)

docker-push: ## Push Docker image
	docker push $(DOCKER_IMAGE):$(DOCKER_TAG)

# ----- Clean -----
clean: ## Clean build artifacts
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/
	rm -rf .pytest_cache/
	rm -rf .mypy_cache/
	rm -rf .ruff_cache/
	rm -rf htmlcov/
	rm -rf .coverage
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete

clean-venv: clean ## Clean including virtual environment
	rm -rf $(VENV)
