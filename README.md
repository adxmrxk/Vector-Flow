# VectorFlow

**Polyglot semantic search platform with end-to-end DevOps lifecycle.**

VectorFlow is a microservices-based semantic search system where each service is written in the language best suited to its job: Go for the API gateway, Rust for high-performance vector math, Python for ML inference, and Next.js for the web UI. The platform ships through a full DevOps stack: Docker Compose for local dev, Helm and raw Kubernetes manifests, Terraform for AWS infrastructure, Ansible and Chef for configuration management, Jenkins for CI/CD, and a CLI for everyday operators.

---

## Table of Contents

- [Project Overview](#project-overview)
- [The Three-Language Architecture](#the-three-language-architecture)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Command Line Interface](#command-line-interface)
- [Deployment Options](#deployment-options)
- [Configuration](#configuration)

---

## Project Overview

### What It Is

A production-grade semantic search platform built as four cooperating services. The Go gateway handles authentication, request routing, and Prometheus metrics. The Python inference service generates vector embeddings using sentence-transformers and stores them in Pinecone. The Rust worker handles CPU-bound result re-ranking and cosine similarity math. A Next.js frontend and an installable `vectorflow` CLI both talk to the same Go gateway.

### The Problem It Solves

Keyword search misses meaning. A query for "vehicle insurance" should match a document that says "car policy," and a query for "scaling solutions" should match articles about L2s, rollups, and sharding even when those exact words don't appear. Semantic search solves this by encoding text into high-dimensional vectors so that proximity in vector space corresponds to similarity in meaning.

Building that system production-ready requires more than one well-chosen library: it requires the right language for each layer (a fast networking layer, a fast math layer, a fast ML layer), strong observability, and a deployment story that doesn't fall apart when the project leaves a single developer's laptop. VectorFlow is built around that full picture.

### What It Does

- Ingests text documents and generates 384-dimensional embeddings using `sentence-transformers/all-MiniLM-L6-v2`
- Stores embeddings in Pinecone for sub-100ms approximate nearest neighbor search
- Performs semantic search by query, returning top-K results ranked by cosine similarity
- Re-ranks results in a Rust worker that boosts scores based on query-term overlap
- Supports single and batch upserts via REST or CLI
- Authenticates requests with JWT and supports optional API key headers
- Emits OpenTelemetry traces from every service into Jaeger
- Exposes Prometheus metrics on every service for Grafana dashboards
- Ships with provisioning for AWS, Kubernetes (Helm + Kustomize), and config-managed VMs (Ansible + Chef)

---

## The Three-Language Architecture

VectorFlow is intentionally polyglot. Each service is written in the language whose strengths match the workload.

| Service       | Language         | Job                                              | Why This Language |
|---------------|------------------|--------------------------------------------------|-------------------|
| **Gateway**   | **Go (Gin)**     | HTTP routing, JWT auth, request fan-out, Prometheus | Go's `net/http` and goroutines make I/O-bound API gateways trivial. Strong typing, excellent observability ecosystem, predictable garbage collection under sustained traffic. |
| **Worker**    | **Rust (Axum + Tokio)** | Vector math, re-ranking, cosine similarity | Rust gives near-C performance for hot loops over float arrays with zero garbage collection pauses. Axum's tower middleware composes cleanly with OpenTelemetry tracing. |
| **Inference** | **Python (FastAPI)** | sentence-transformers embeddings, Pinecone client | Python is where the ML ecosystem lives. PyTorch, transformers, sentence-transformers, and the official Pinecone SDK are all first-class here. Trying to use any other language for this layer would be fighting the world. |
| **Frontend**  | **Next.js + TypeScript** | Web UI for search and ingest                 | App Router, React Server Components, Tailwind. Standard modern frontend. |

The split also means each service can be tuned, scaled, and replaced independently. If embedding throughput becomes the bottleneck, the inference service scales horizontally without touching the gateway. If re-ranking logic becomes a bottleneck, the Rust worker is the only thing that needs to change.

---

## How It Works

A search request flows through all three backend services:

```
        ┌──────────────────────────┐
        │  Client (UI or CLI)      │   POST /v1/search { "query": "...", "top_k": 10 }
        └─────────────┬────────────┘
                      ▼
   1.  Go Gateway (port 8080)
       • JWT auth middleware validates bearer token
       • OpenTelemetry span starts
       • Forwards request to inference service
                      │
                      ▼
   2.  Python Inference (port 8082)
       • Generates 384-d embedding via sentence-transformers
       • Queries Pinecone ANN index for top-K candidates
       • Returns ranked candidates with metadata
                      │
                      ▼
   3.  Rust Worker (port 8081)
       • Receives candidates + original query
       • Computes query-term overlap with each result's text
       • Boosts scores: score * (1 + overlap * 0.1)
       • Sorts and truncates to top_k
                      │
                      ▼
   4.  Go Gateway
       • Adds gateway latency metric
       • Returns final ranked results to client
                      │
                      ▼
        ┌──────────────────────────┐
        │  Client receives JSON    │   { "results": [...], "latency_ms": 47 }
        └──────────────────────────┘
```

Ingest follows a parallel path: client posts text to `/v1/upsert`, the gateway forwards to the inference service, the inference service embeds it and upserts to Pinecone, and the gateway returns a confirmation.

---

## Architecture

```
                       ┌────────────────────────────────────┐
                       │         CLIENT LAYER               │
                       │   Next.js UI   /   vectorflow CLI  │
                       └─────────────────┬──────────────────┘
                                         ▼
                       ┌────────────────────────────────────┐
                       │         GATEWAY LAYER              │
                       │   Go (Gin) on :8080                │
                       │   JWT auth, CORS, Prometheus       │
                       └─────────────────┬──────────────────┘
                                         ▼
        ┌──────────────────────────────────────────────────────┐
        │                  COMPUTE LAYER                        │
        │  ┌─────────────────────┐   ┌────────────────────────┐│
        │  │  Rust Worker (8081) │   │  Python Inference (8082)││
        │  │  Axum + Tokio       │   │  FastAPI + Uvicorn      ││
        │  │  Re-rank, cosine    │   │  sentence-transformers  ││
        │  └─────────────────────┘   └────────────────────────┘│
        └──────────────────────────────────────────────────────┘
                                         ▼
        ┌──────────────────────────────────────────────────────┐
        │                  STORAGE LAYER                        │
        │     Pinecone (managed vector database)                │
        │     sub-100ms ANN search at scale                     │
        └──────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────┐
        │                OBSERVABILITY LAYER                    │
        │  OpenTelemetry  ──▶  Jaeger (distributed traces)      │
        │  Prometheus     ──▶  Grafana (metrics + dashboards)   │
        │  structlog / zerolog / tracing (structured JSON logs) │
        └──────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────┐
        │              INFRASTRUCTURE LAYER                     │
        │  Terraform (AWS), Helm + Kustomize (K8s),             │
        │  Ansible + Chef (config mgmt), Jenkins (CI/CD)        │
        └──────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Application Runtime

| Component       | Technology               | Notes |
|-----------------|--------------------------|-------|
| Gateway         | **Go 1.21 + Gin**        | Routing, middleware, graceful shutdown. zerolog for structured logging. |
| Worker          | **Rust + Axum + Tokio**  | Async-first runtime, tower middleware, tracing crate for OTel integration. |
| Inference       | **Python 3.11 + FastAPI** | structlog for JSON logs, sentence-transformers for embeddings, official Pinecone client. |
| Frontend        | **Next.js + React + Tailwind** | App Router, TypeScript, Vite-style dev experience. |
| CLI             | **Python (Click)**       | Distributed as a Python package. Talks to the Go gateway over HTTPS. |

### Embeddings and Vector Store

| Component                 | Purpose |
|---------------------------|---------|
| **sentence-transformers** | Generates 384-dimensional embeddings using `all-MiniLM-L6-v2`. Good quality-to-speed tradeoff. |
| **Pinecone**              | Managed vector database. Sub-100ms ANN at scale, no infrastructure to operate. |
| **Cosine similarity**     | Rust-implemented similarity scoring for re-ranking candidates from Pinecone. |

### Security

| Component            | Purpose |
|----------------------|---------|
| **JWT auth**         | Stateless authentication on all `/v1/*` routes; gateway-level middleware. |
| **API key headers**  | Alternative authentication path for service-to-service calls. |
| **CORS middleware**  | Configurable origin allow-list for frontend integration. |
| **InSpec compliance** | Chef-side security baseline checks (`chef/compliance/vectorflow`). |

### Observability

| Component                 | Purpose |
|---------------------------|---------|
| **OpenTelemetry**         | Distributed tracing across all three backend services via OTLP HTTP exporter. |
| **Jaeger**                | Trace storage and UI for following a request end-to-end. |
| **Prometheus**            | Metrics scraping from gateway, worker, and inference. |
| **Grafana**               | Dashboards over Prometheus data. |
| **zerolog / structlog / tracing** | Native structured JSON logging in each service. |

### Configuration Management

| Tool       | Purpose |
|------------|---------|
| **Ansible** | Playbooks for local dev setup, cluster setup, full VectorFlow deployment, and security hardening. |
| **Chef**    | Cookbooks (`vectorflow_app`, `vectorflow_base`, `vectorflow_docker`, `vectorflow_kubernetes`, `vectorflow_security`), policies, environments, and Test Kitchen integration. InSpec compliance profiles. |

### Infrastructure as Code

| Tool          | Purpose |
|---------------|---------|
| **Terraform** | AWS infrastructure (`terraform/main.tf`). Reusable variables and outputs. |
| **Helm**      | Production-grade Kubernetes chart with HPA, ingress, PVC, and serviceaccount templates. |
| **Kustomize** | Raw Kubernetes manifests per service (gateway, worker, inference, frontend) with NetworkPolicy. |

### CI/CD

| Tool             | Purpose |
|------------------|---------|
| **Jenkins**      | `Jenkinsfile` defines the full multi-stage pipeline. JCasC config in `jenkins/config/`. |
| **Docker**       | Per-service Dockerfiles with multi-stage builds. |
| **Docker Compose** | Local development orchestration. |

### Tooling

| Tool         | Purpose |
|--------------|---------|
| **Makefile** | Single entry point for every common task across all services (`make test`, `make docker-up`, `make k8s-deploy`, `make helm-install`, `make chef-test`, ...). |
| **pytest**   | Unit and integration tests for Python services. |
| **cargo**    | Rust test runner via `cargo test`. |
| **go test**  | Go test runner. |

---

## Project Structure

```
vectorflow/
│
├── go/                               Gateway service (Go + Gin)
│   ├── cmd/gateway/main.go           Entry point with graceful shutdown
│   ├── internal/
│   │   ├── api/handlers.go           REST handlers: /health, /v1/embeddings, /v1/search, /v1/upsert
│   │   ├── api/auth.go               Register, login, refresh, /me, validate-token
│   │   ├── middleware/auth.go        JWT validation middleware
│   │   ├── middleware/tracing.go     OpenTelemetry span middleware
│   │   ├── service/client.go         HTTP client for worker + inference
│   │   ├── telemetry/tracing.go      OTel exporter setup
│   │   ├── config/config.go          Env-driven config struct
│   │   └── models/models.go          Request and response types
│   ├── go.mod
│   ├── Dockerfile
│   └── Makefile
│
├── rust/                             Worker service (Rust + Axum)
│   ├── src/main.rs                   Rerank, cosine similarity, OTel setup
│   ├── Cargo.toml
│   ├── Dockerfile
│   └── Makefile
│
├── python/                           Inference service (Python + FastAPI)
│   ├── app/
│   │   ├── main.py                   uvicorn entrypoint, structlog config
│   │   ├── api.py                    FastAPI routes
│   │   ├── config.py                 Pydantic settings
│   │   ├── models.py                 Request and response schemas
│   │   └── telemetry.py              OTel exporter
│   ├── services/
│   │   ├── embedding.py              sentence-transformers wrapper
│   │   └── vector_store.py           Pinecone client wrapper
│   ├── tests/test_api.py
│   ├── pyproject.toml
│   ├── requirements.txt
│   ├── Dockerfile
│   └── Makefile
│
├── frontend/                         Next.js web UI
│   ├── app/page.tsx                  Search and ingest UI
│   ├── lib/api.ts                    Typed gateway client
│   ├── lib/types.ts                  Shared types
│   ├── Dockerfile
│   └── package.json
│
├── cli/                              vectorflow CLI (Python)
│   ├── vectorflow_cli/main.py        Click subcommands
│   ├── vectorflow_cli/client.py      Gateway HTTP client
│   ├── pyproject.toml                Installs the `vectorflow` entry point
│   └── README.md
│
├── docker-compose.yml                Full local stack (all 3 backend services + frontend + Jaeger/Prom/Grafana profiles)
│
├── k8s/                              Raw Kubernetes manifests (Kustomize)
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── ingress.yaml
│   ├── network-policy.yaml
│   ├── gateway/                      Deployment + Service per backend service
│   ├── worker/
│   ├── inference/
│   ├── frontend/
│   └── kustomization.yaml
│
├── helm/vectorflow/                  Helm chart (preferred K8s path)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/                    Templated deployments, services, HPA, ingress, PVC, RBAC
│
├── terraform/                        AWS infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── ansible/                          Configuration management + deployment
│   ├── ansible.cfg
│   ├── inventory/
│   ├── playbooks/
│   │   ├── local-dev-setup.yml
│   │   ├── cluster-setup.yml
│   │   ├── deploy-vectorflow.yml
│   │   └── security-hardening.yml
│   └── requirements.yml
│
├── chef/                             Alternate configuration management
│   ├── cookbooks/                    vectorflow_app, _base, _docker, _kubernetes, _security
│   ├── policies/                     base, security, standalone, worker
│   ├── roles/                        server, standalone, worker
│   ├── environments/                 dev, staging, prod
│   ├── compliance/vectorflow/        InSpec compliance profile
│   ├── kitchen.yml                   Test Kitchen integration tests
│   └── Berksfile
│
├── jenkins/                          CI/CD platform
│   ├── config/jenkins-config.yaml    Jenkins Configuration as Code
│   └── scripts/smoke-tests.sh
│
├── scripts/                          Operational scripts
│   ├── setup.sh                      Initial project setup
│   ├── dev-setup.sh                  Dev environment with hot reload
│   ├── vf                            CLI shim
│   ├── vf-search.sh                  Quick search wrapper
│   ├── vf-health.sh                  System health probe
│   ├── install-tools.sh              Install required tooling
│   ├── check-deps.sh                 Verify dependencies
│   └── cleanup.sh                    Resource cleanup (local + AWS)
│
├── tests/integration/                Cross-service integration tests
│
├── docs/LOCAL_DEVELOPMENT.md         Detailed local dev guide
├── Jenkinsfile                       Multi-stage CI/CD pipeline
├── Makefile                          Root orchestration entrypoint
├── pytest.ini                        Python test config
└── .env.example                      Environment variable template
```

---

## Getting Started

### Prerequisites

- Docker + Docker Compose (always required)
- A Pinecone account and API key
- For native development: Go 1.21+, Rust 1.74+, Python 3.11+, Node.js 18+
- For cloud deploys: AWS CLI, Terraform 1.6+, `kubectl`, `helm` 3.x

### One-Command Local Startup

```bash
cp .env.example .env
# Edit .env to set PINECONE_API_KEY and PINECONE_INDEX_NAME

make local-dev
```

`make local-dev` runs `docker compose up -d` and prints the live endpoint URLs.

| Service        | URL                       |
|----------------|---------------------------|
| Frontend       | http://localhost:3000     |
| Gateway        | http://localhost:8080     |
| Worker         | http://localhost:8081     |
| Inference      | http://localhost:8082     |

To include the observability stack (Jaeger, Prometheus, Grafana):

```bash
docker compose --profile monitoring up -d
```

| Service          | URL                       | Login          |
|------------------|---------------------------|----------------|
| Jaeger UI        | http://localhost:16686    |                |
| Prometheus       | http://localhost:9090     |                |
| Grafana          | http://localhost:3001     | admin / admin  |

### First Search

```bash
# Add a document
curl -X POST http://localhost:8080/v1/upsert \
  -H "Content-Type: application/json" \
  -d '{"id": "doc-1", "text": "Cars and motorcycles are types of vehicles."}'

# Run a semantic search
curl -X POST http://localhost:8080/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "automobile transportation", "top_k": 5}'
```

### Tear Down

```bash
make cleanup-local      # Stops containers + Minikube + prunes Docker
make cleanup            # Includes AWS resource cleanup (interactive)
```

---

## Command Line Interface

VectorFlow ships an installable CLI that gives operators and power users full access without touching curl.

### Install

```bash
make cli-install        # Installs `vectorflow` in editable mode
```

### Common Commands

```bash
vectorflow health                    # Check gateway, worker, inference health
vectorflow status                    # Model info and Pinecone index stats

vectorflow search "query text"       # Semantic search (default top_k=10)
vectorflow search "query" -k 5       # Limit to top 5
vectorflow search "query" --json     # Machine-readable output

vectorflow upsert doc-1 "text content"
vectorflow upsert doc-2 "text" -m '{"category": "AI"}'
vectorflow batch-upsert data.json
vectorflow batch-upsert data.json --dry-run

vectorflow embed "text to embed"     # Returns the raw 384-d vector
```

### Configuration

```bash
export VECTORFLOW_GATEWAY_URL=http://localhost:8080
# Or pass per-invocation:
vectorflow --gateway-url http://prod.example.com search "query"
```

Shell shortcuts wrapping the CLI live in `scripts/`:

```bash
./scripts/vf search "query"          # CLI wrapper
./scripts/vf-search.sh "query"       # Pure-bash quick search
./scripts/vf-health.sh               # Pure-bash health check
```

---

## Deployment Options

VectorFlow is deliberately deployable through every major DevOps tooling stack. Pick whichever matches your environment.

### 1. Docker Compose (Local Development)

```bash
make local-dev
```

All services run as containers on a single Docker network. Zero cloud cost.

### 2. Kubernetes via Helm (Production Recommended)

```bash
make helm-lint                      # Lint the chart
make helm-install                   # Install to current cluster
make helm-upgrade                   # Upgrade to a new release
```

The chart includes templated deployments for all four services, HorizontalPodAutoscaler, NGINX Ingress, PersistentVolumeClaim for the model cache, and a ServiceAccount with appropriate RBAC.

### 3. Kubernetes via Kustomize (Raw Manifests)

```bash
make k8s-deploy
make k8s-status
make k8s-delete
```

Use this when you want full control over every resource without Helm's templating layer.

### 4. AWS via Terraform

```bash
make tf-init
make tf-plan
make tf-apply
```

Provisions the AWS infrastructure declared in `terraform/main.tf`. Customize variables in `terraform/terraform.tfvars`.

### 5. Configuration Management via Ansible

```bash
make ansible-setup                  # Run local-dev-setup.yml
make ansible-deploy                 # Run deploy-vectorflow.yml
```

Useful for managing VMs or bare-metal nodes where Kubernetes is overkill.

### 6. Configuration Management via Chef

```bash
make chef-lint                      # Lint all cookbooks
make chef-test                      # Run cookbook tests
make chef-converge                  # Apply locally
make chef-compliance                # Run InSpec security profile
make chef-kitchen                   # Full Test Kitchen integration tests
```

Includes five cookbooks (app, base, docker, kubernetes, security), three policies, three roles, environment configs for dev/staging/prod, and an InSpec compliance profile.

### 7. CI/CD via Jenkins

The repo includes a full multi-stage `Jenkinsfile` and Jenkins Configuration as Code in `jenkins/config/`. Smoke tests live in `jenkins/scripts/smoke-tests.sh`.

```bash
make ci-build                       # Run the CI pipeline locally
make ci-deploy                      # Run the deploy pipeline locally
```

---

## Configuration

All configuration is environment-variable driven. Copy `.env.example` to `.env` and adjust.

### Required

| Variable                | Description                       |
|-------------------------|-----------------------------------|
| `PINECONE_API_KEY`      | API key for the Pinecone account  |
| `PINECONE_INDEX_NAME`   | Name of the Pinecone index        |

### Service Ports

| Variable                  | Description              | Default |
|---------------------------|--------------------------|---------|
| `GO_GATEWAY_PORT`         | Gateway HTTP port        | `8080`  |
| `RUST_WORKER_PORT`        | Worker HTTP port         | `8081`  |
| `PYTHON_INFERENCE_PORT`   | Inference HTTP port      | `8082`  |
| `FRONTEND_PORT`           | Next.js dev port         | `3000`  |

### Inference

| Variable                | Description                                       | Default |
|-------------------------|---------------------------------------------------|---------|
| `MODEL_NAME`            | sentence-transformers model identifier            | `sentence-transformers/all-MiniLM-L6-v2` |
| `MODEL_CACHE_DIR`       | Where downloaded models are cached                | `./models` |
| `BATCH_SIZE`            | Embedding batch size                              | `32`    |
| `MAX_SEQUENCE_LENGTH`   | Max tokens per input                              | `512`   |

### Authentication

| Variable           | Description                                | Default |
|--------------------|--------------------------------------------|---------|
| `AUTH_ENABLED`     | Require JWT on `/v1/*` routes              | `false` |
| `JWT_SECRET`       | Symmetric signing key                      | (set in prod) |
| `JWT_EXPIRY`       | Token lifetime                             | `24h`   |
| `API_KEY_HEADER`   | Header name for API key authentication     | `X-API-Key` |

### Observability

| Variable                       | Description                              | Default                |
|--------------------------------|------------------------------------------|------------------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT`  | OTLP HTTP endpoint                       | `http://jaeger:4318`   |
| `OTEL_TRACES_ENABLED`          | Enable trace export                      | `true`                 |
| `PROMETHEUS_ENABLED`           | Expose `/metrics`                        | `true`                 |
| `PROMETHEUS_PORT`              | Prometheus port                          | `9090`                 |
| `GRAFANA_PORT`                 | Grafana port                             | `3001`                 |
