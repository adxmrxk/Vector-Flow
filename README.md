# VectorFlow

**Polyglot semantic search platform with end-to-end DevOps lifecycle.**

VectorFlow is a microservices-based semantic search system where each service is written in the language best suited to its job: Go for the API gateway, Rust for high-performance vector math, Python for ML inference, and Next.js for the web UI. It ships through a full DevOps stack — Docker Compose, Helm/Kustomize, Terraform, Ansible/Chef, and Jenkins.

---

## Overview

Keyword search misses meaning: a query for "vehicle insurance" should match a document that says "car policy" even though the words never overlap. VectorFlow solves this by encoding text into vectors so proximity in vector space corresponds to similarity in meaning — and covers vector search's own blind spot (missing exact-match terms like product IDs) with a hybrid BM25 keyword index fused in via Reciprocal Rank Fusion.

**What it does:**
- Generates 384-dimensional embeddings (`sentence-transformers/all-MiniLM-L6-v2`) and stores them in Pinecone
- Hybrid search: dense (Pinecone) + keyword (SQLite FTS5/BM25) results fused with Reciprocal Rank Fusion
- Chunks documents longer than the model's token limit so nothing is silently truncated
- Re-ranks results in a Rust worker based on query-term overlap
- JWT-scoped multi-tenancy: authenticated requests are confined to the caller's own namespace
- Redis-backed search result caching, invalidated automatically on upsert
- Full observability: OpenTelemetry traces (Jaeger), Prometheus metrics (Grafana), structured JSON logs
- Ships with provisioning for AWS, Kubernetes (Helm + Kustomize), and config-managed VMs (Ansible + Chef)

**Measured performance** (local Docker Compose, Pinecone serverless `us-east-1`, 5,006 vectors, CPU embeddings):

| Metric | Result |
|--------|--------|
| Bulk ingest | 5,000 docs, 0 failures, 32.1s (~156 docs/sec) |
| Search latency p50 / p95 / p99 | 69 ms / 131 ms / 257 ms |
| Batch embedding throughput | 595 docs/sec (6.1x faster than one-at-a-time) |
| Gateway health check latency | 80 ms (2x faster after parallelizing downstream checks) |

Latencies are client-observed round trip, including embedding generation, the network hop to Pinecone, and Docker port forwarding.

---

## How It Works

```
Client (UI/CLI) → Go Gateway (auth, tenant-scoped namespace, cache check)
                → Python Inference (embed, dense + keyword search, fuse)
                → Rust Worker (re-rank by query-term overlap)
                → Go Gateway (cache write, metrics) → Client
```

A cache hit short-circuits straight back to the client without touching Pinecone. Ingest follows a parallel path: the gateway resolves the namespace, the inference service chunks and embeds the text, then upserts to both Pinecone and the keyword index.

The three-language split is deliberate: Go's goroutines make an I/O-bound gateway trivial, Rust gives near-C performance for the re-rank hot loop with no GC pauses, and Python is where the ML ecosystem (sentence-transformers, Pinecone's SDK) actually lives. Each service scales and redeploys independently.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Gateway | Go 1.22, Gin, zerolog, JWT auth, Redis cache |
| Worker | Rust, Axum, Tokio |
| Inference | Python 3.11, FastAPI, sentence-transformers, Pinecone, SQLite FTS5 |
| Frontend | Next.js, React, TypeScript, Tailwind |
| CLI | Python (Click) |
| Observability | OpenTelemetry, Jaeger, Prometheus, Grafana |
| Infra as Code | Terraform (AWS), Helm, Kustomize, Kubernetes |
| Config Management | Ansible, Chef, InSpec |
| CI/CD | Jenkins, Docker, Docker Compose |
| Testing | pytest, cargo test, go test, Jest |

---

## Getting Started

**Prerequisites:** Docker + Docker Compose, a Pinecone account and API key. For native development: Go 1.22+, Rust 1.74+, Python 3.11+, Node 18+.

```bash
cp .env.example .env
# Edit .env to set PINECONE_API_KEY and PINECONE_INDEX_NAME

make local-dev          # docker compose up -d, prints live endpoint URLs
```

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Gateway | http://localhost:8080 |
| Worker / Inference | http://localhost:8081 / :8082 |

Add `--profile monitoring` to `docker compose up -d` for Jaeger (16686), Prometheus (9090) and Grafana (3001, admin/admin).

**Try it:**

```bash
curl -X POST http://localhost:8080/v1/upsert \
  -H "Content-Type: application/json" \
  -d '{"id": "doc-1", "text": "Cars and motorcycles are types of vehicles."}'

curl -X POST http://localhost:8080/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "automobile transportation", "top_k": 5}'
```

Tear down with `make cleanup-local` (or `make cleanup` to include AWS resources).

---

## Command Line Interface

```bash
make cli-install                     # Installs `vectorflow` in editable mode

vectorflow health                    # Check gateway, worker, inference health
vectorflow search "query text" -k 5
vectorflow upsert doc-1 "text content"
vectorflow batch-upsert data.json
vectorflow embed "text to embed"     # Returns the raw 384-d vector
```

---

## Deployment Options

| Path | Command | Status |
|------|---------|--------|
| Docker Compose | `make local-dev` | Verified running |
| Kubernetes (Helm) | `make helm-install` | Verified deployed |
| Kubernetes (Kustomize) | `make k8s-deploy` | Verified deployed |
| AWS (Terraform) | `make tf-plan` / `make tf-apply` | Validated, **not applied** (~$105/mo, not free tier) |
| Ansible | `make ansible-deploy` | Syntax-checked, not run against real hosts |
| Chef | `make chef-kitchen` | Base suite verified via live convergence; see `chef/` |
| Jenkins | `Jenkinsfile` + `jenkins/config/` | JCasC boots clean, pipeline linted; no full build run |

See `docs/LOCAL_DEVELOPMENT.md` for a detailed walkthrough of any of these.

---

## Configuration

All configuration is environment-variable driven — copy `.env.example` to `.env` and adjust. The required variables:

| Variable | Description |
|----------|--------------|
| `PINECONE_API_KEY` | API key for the Pinecone account |
| `PINECONE_INDEX_NAME` | Name of the Pinecone index |

`.env.example` documents the rest (ports, auth, caching, model settings, observability) with sensible local-dev defaults.
