# VectorFlow Local Development Guide

This guide explains how to run VectorFlow entirely on your local machine with **$0.00 cloud costs**. This is the recommended setup for development and demos.

## The Zero-Cost Philosophy

| Scenario | AWS Cost | Pinecone Cost | Risk |
|----------|----------|---------------|------|
| **Local Demo (Minikube)** | $0.00 | $0.00 (Starter tier) | None |
| **Hybrid (Local + API)** | $0.00 | $0.00 | Extremely low |
| **Full Cloud** | Variable | Variable | Use `cleanup.sh` after |

## Prerequisites

### Required Tools

```bash
# Check if you have everything
./scripts/check-deps.sh

# Or manually verify:
docker --version      # Docker Desktop 20+
kubectl version       # Kubernetes CLI
minikube version      # Local K8s cluster
go version            # Go 1.21+
cargo --version       # Rust 1.70+
python3 --version     # Python 3.10+
node --version        # Node 18+
```

### Install Missing Tools

**Windows (with Chocolatey):**
```powershell
choco install docker-desktop minikube kubernetes-cli golang rust python nodejs
```

**macOS (with Homebrew):**
```bash
brew install docker minikube kubectl go rust python node
```

**Linux (Ubuntu/Debian):**
```bash
# Docker
curl -fsSL https://get.docker.com | sh

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
```

## Quick Start (5 Minutes)

### Option 1: Docker Compose (Simplest)

Run the entire stack without Kubernetes:

```bash
# Start all services
make docker-up

# Or directly:
docker compose up -d

# View logs
docker compose logs -f

# Access:
# - Frontend: http://localhost:3000
# - Gateway:  http://localhost:8080
# - Worker:   http://localhost:8081
# - Inference: http://localhost:8082

# Stop
make docker-down
```

### Option 2: Minikube (Production-Like)

Run with local Kubernetes for a realistic environment:

```bash
# 1. Start Minikube
minikube start --cpus=4 --memory=8192 --driver=docker

# 2. Enable required addons
minikube addons enable ingress
minikube addons enable metrics-server

# 3. Point Docker to Minikube's registry
eval $(minikube docker-env)

# 4. Build images inside Minikube
make docker-build

# 5. Deploy to Kubernetes
make k8s-deploy

# 6. Access services
minikube service vectorflow-frontend -n vectorflow
# Or use port-forward:
kubectl port-forward svc/vectorflow-gateway 8080:8080 -n vectorflow
```

## Development Workflow

### Service URLs (Local)

All services default to `localhost` for zero cloud dependency:

| Service | Local URL | Purpose |
|---------|-----------|---------|
| Frontend | http://localhost:3000 | Web UI |
| Gateway (Go) | http://localhost:8080 | API routing |
| Worker (Rust) | http://localhost:8081 | Re-ranking |
| Inference (Python) | http://localhost:8082 | Embeddings |
| Prometheus | http://localhost:9090 | Metrics |
| Grafana | http://localhost:3001 | Dashboards |

### Environment Configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Key settings for local development:

```bash
# .env - Local Development Settings
ENVIRONMENT=development
DEBUG=true

# Service Discovery (all localhost)
WORKER_SERVICE_URL=http://localhost:8081
INFERENCE_SERVICE_URL=http://localhost:8082
GATEWAY_SERVICE_URL=http://localhost:8080

# Pinecone (use free starter tier)
PINECONE_API_KEY=your-free-api-key
PINECONE_ENVIRONMENT=us-east-1
PINECONE_INDEX_NAME=vectorflow-dev

# Kubernetes context
K8S_CONTEXT=minikube
K8S_NAMESPACE=vectorflow
```

### Hot Reload Development

For active development with hot reloading:

```bash
# Start dev environment with watch mode
make dev

# Or run services individually:

# Terminal 1: Go Gateway
cd go && go run cmd/gateway/main.go

# Terminal 2: Rust Worker
cd rust && cargo watch -x run

# Terminal 3: Python Inference
cd python && source venv/bin/activate && uvicorn app.main:app --reload

# Terminal 4: Next.js Frontend
cd frontend && npm run dev
```

## Minikube Commands Reference

### Cluster Management

```bash
# Start cluster
minikube start --cpus=4 --memory=8192

# Stop cluster (preserves data)
minikube stop

# Delete cluster (clean slate)
minikube delete

# Check status
minikube status

# SSH into node
minikube ssh

# View dashboard
minikube dashboard
```

### Resource Management

```bash
# View all resources
kubectl get all -n vectorflow

# View pods
kubectl get pods -n vectorflow

# View services
kubectl get svc -n vectorflow

# View logs
kubectl logs -f deployment/vectorflow-gateway -n vectorflow

# Describe pod (debugging)
kubectl describe pod <pod-name> -n vectorflow

# Execute into pod
kubectl exec -it <pod-name> -n vectorflow -- /bin/sh
```

### Networking

```bash
# Expose service via NodePort
minikube service vectorflow-frontend -n vectorflow

# Port forward (preferred for development)
kubectl port-forward svc/vectorflow-gateway 8080:8080 -n vectorflow

# Get Minikube IP
minikube ip

# Tunnel for LoadBalancer services
minikube tunnel
```

## Testing Your Setup

### Health Checks

```bash
# Using the CLI
./scripts/vf-health.sh

# Or use curl:
curl http://localhost:8080/health    # Gateway
curl http://localhost:8081/health    # Worker
curl http://localhost:8082/health    # Inference
```

### Sample Search Request

```bash
# Via CLI
./scripts/vf-search.sh "machine learning best practices"

# Via curl
curl -X POST http://localhost:8080/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "machine learning best practices", "top_k": 5}'
```

### Run Tests

```bash
# All tests
make test

# Individual services
cd go && go test ./...
cd rust && cargo test
cd python && pytest
cd frontend && npm test
```

## Troubleshooting

### Minikube Won't Start

```bash
# Reset Docker
minikube delete
docker system prune -a
minikube start --driver=docker

# Try different driver
minikube start --driver=hyperv  # Windows
minikube start --driver=hyperkit  # macOS
```

### Images Not Found in Minikube

```bash
# Point shell to Minikube's Docker daemon
eval $(minikube docker-env)

# Rebuild images
make docker-build

# Verify images exist
docker images | grep vectorflow
```

### Pods Stuck in Pending/CrashLoopBackOff

```bash
# Check pod events
kubectl describe pod <pod-name> -n vectorflow

# Check logs
kubectl logs <pod-name> -n vectorflow --previous

# Common fixes:
# - Increase Minikube memory: minikube start --memory=8192
# - Check image pull policy: imagePullPolicy: Never (for local images)
```

### Cannot Connect to Services

```bash
# Verify services are running
kubectl get svc -n vectorflow

# Use port-forward instead of NodePort
kubectl port-forward svc/vectorflow-gateway 8080:8080 -n vectorflow

# Check Minikube tunnel (for LoadBalancer)
minikube tunnel
```

### Python Model Download Slow/Failing

```bash
# Pre-download models locally
python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Mount model cache to container
# Already configured in docker-compose.yml and k8s manifests
```

## Switching to Cloud (When Needed)

When you're ready to deploy to AWS:

```bash
# 1. Update .env for cloud
ENVIRONMENT=production
K8S_CONTEXT=aws-eks-context

# 2. Ensure billing alarm is set ($0.01 threshold)
# 3. Deploy with Ansible
make ansible-deploy

# 4. When done, ALWAYS run cleanup:
./scripts/cleanup.sh
```

## Cost Protection Checklist

Before ANY cloud deployment:

- [ ] AWS billing alarm set at $0.01
- [ ] `.env` file has `ENVIRONMENT=development`
- [ ] Using Pinecone Starter (free) tier
- [ ] All API keys are in `.env` (not committed)
- [ ] Know how to run `./scripts/cleanup.sh`

## Resource Usage (Local)

Expected resource consumption on your machine:

| Service | CPU | Memory | Disk |
|---------|-----|--------|------|
| Minikube | 2-4 cores | 4-8 GB | 20 GB |
| Docker Compose | 2 cores | 4 GB | 5 GB |
| ML Models | - | 500 MB | 500 MB |

Minimum recommended specs:
- **CPU:** 4+ cores
- **RAM:** 16 GB (8 GB minimum)
- **Disk:** 50 GB free space

## Next Steps

1. Run `make docker-up` to start locally
2. Open http://localhost:3000
3. Try a sample search
4. Explore the codebase
5. Make changes and see hot reload
6. Run `make test` before committing
