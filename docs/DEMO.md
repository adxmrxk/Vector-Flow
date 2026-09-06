# Running & Demoing VectorFlow

A tested walkthrough for showing this project to someone. Every command here
has been run against this repo.

---

## Prerequisites

| Need | Why |
|------|-----|
| Docker Desktop running | Everything runs in containers |
| `.env` with a real `PINECONE_API_KEY` | Search and upsert 503 without it |
| ~6 GB free disk | Images total ~3.1 GB plus the model cache volume |

Nothing else. Go, Rust, Python and Node are only needed if you want to run the
test suites outside Docker.

### One-time setup

```bash
cp .env.example .env
# edit .env and set PINECONE_API_KEY=pcsk_...
```

Leave `PINECONE_ENVIRONMENT=us-east-1` and `PINECONE_INDEX_NAME=vectorflow-index`
alone — the free Pinecone tier is `us-east-1` only, and the app creates the
index itself on first boot (384 dimensions, cosine).

---

## Start it

```bash
docker compose --profile monitoring --profile tracing up -d
```

That brings up all seven services. Without the profiles you get the four
application services only.

**Timing:** if the images are already built, the stack is healthy in ~20s.
A cold first run downloads the embedding model (~90 MB) and takes 1–2 minutes;
after that the model is cached in a Docker volume.

Check everything is up:

```bash
docker compose --profile monitoring --profile tracing ps
./scripts/vf-health.sh          # expects: All critical services healthy
```

---

## What to show, in order

### 1. The UI — http://localhost:3000

Search box backed by the whole stack. Good opening shot.

### 2. Semantic search actually being semantic

This is the moment worth landing. Add a document, then search for it using
**words that do not appear in it**:

```bash
curl -X POST http://localhost:8080/v1/upsert \
  -H "Content-Type: application/json" \
  -d '{"id":"demo-1","text":"Cars and motorcycles are types of vehicles.","metadata":{"text":"Cars and motorcycles are types of vehicles."}}'

curl -X POST http://localhost:8080/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query":"automobile transportation","top_k":5}'
```

`automobile transportation` matches `Cars and motorcycles...` at ~0.55 with zero
shared keywords. That is the whole point of the product in one command.

### 3. The three-language request path

A single search traverses all three backend services:

```
Go gateway  →  Python inference (embed + Pinecone ANN)  →  Rust worker (re-rank)
```

Prove it rather than assert it:

```bash
# the Rust worker's own counter goes up when you search
curl -s http://localhost:8081/metrics | grep vectorflow_worker_requests_total
```

Then open **Jaeger — http://localhost:16686**, pick service `vectorflow-gateway`,
operation `POST /v1/search`, and open a trace. You will see spans from
**gateway, inference and worker in one trace**.

### 4. Grafana — http://localhost:3001 (admin / admin)

Dashboard **VectorFlow Overview** (folder: VectorFlow). 18 panels: request rate,
p50/p95/p99 latency, error ratio, per-service downstream latency, worker rerank
throughput, inference latency. Generate traffic first or the graphs are flat:

```bash
for i in $(seq 1 20); do
  curl -s -o /dev/null -X POST http://localhost:8080/v1/search \
    -H "Content-Type: application/json" \
    -d '{"query":"vehicle insurance","top_k":5}'
done
```

### 5. The CLI

```bash
make cli-install          # or: pip install -e ./cli
vectorflow health
vectorflow status         # model info + live index stats
vectorflow embed "text to embed"
vectorflow search "battery powered transport" -k 3
vectorflow search "insurance" -k 2 --json
```

### 6. Tests, if asked

```bash
cd go && go test ./...                        # 43 tests, 7 packages
cd frontend && npm test                       # 6 tests
pytest tests/                                 # 26 integration tests (stack must be up)
```

Rust tests need `cargo`; if it isn't installed:
`docker run --rm -v "$PWD/rust:/app" -w /app rust:alpine cargo test` (8 tests).

---

## Talking points that hold up to scrutiny

- **Polyglot for real reasons.** Go for I/O-bound routing, Rust for the CPU-bound
  re-rank hot loop, Python because the ML ecosystem lives there.
- **Distributed tracing works end to end.** W3C trace context propagates from the
  gateway through both downstream services — one trace, all three languages.
- **Measured, not guessed.** 5,000-document ingest at ~156 docs/s; search p50 69ms,
  p95 131ms over 60 queries. Be honest that the p95 is client-observed round-trip
  including embedding and a network hop to `us-east-1`, not Pinecone's ANN time.
- **Both Kubernetes paths deploy.** `kubectl apply -k k8s/` (19 resources) and
  `helm install` both verified against a real cluster.

---

## Ports

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Gateway | http://localhost:8080 |
| Rust worker | http://localhost:8081 |
| Python inference | http://localhost:8082 |
| Grafana | http://localhost:3001 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Jaeger | http://localhost:16686 |

---

## If something is wrong

**`Vector store not connected` / 503 on search or upsert**
`PINECONE_API_KEY` is missing or invalid. Check with:
`docker logs vectorflow-inference 2>&1 | grep -i pinecone` — you want
`Connected to Pinecone`.

**Inference unhealthy on first boot**
It is downloading the model. Give it 1–2 minutes; watch with
`docker logs -f vectorflow-inference`.

**`/v1/index` shows fewer vectors than you just added**
Pinecone's `describe_index_stats` is eventually consistent and can lag a minute
or more behind writes. Searches see the data immediately.

**Port already in use**
Change the port in `.env` (`GO_GATEWAY_PORT`, `FRONTEND_PORT`, ...) and restart.

**Ran out of disk after rebuilding images**
Docker's virtual disk grows and never shrinks on its own. Reclaim it with an
admin PowerShell:

```powershell
wsl --shutdown
diskpart
  select vdisk file="$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
  attach vdisk readonly
  compact vdisk
  detach vdisk
```

---

## Stop it

```bash
docker compose --profile monitoring --profile tracing down    # keeps volumes
docker compose --profile monitoring --profile tracing down -v # also drops the model cache
```
