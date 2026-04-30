# VectorFlow CLI

Command-line interface for VectorFlow.

## Installation

```bash
cd cli && pip install -e .
```

## Commands

```bash
# Health & status
vectorflow health              # Check all services
vectorflow status              # Model info, index stats

# Search
vectorflow search "query"      # Semantic search
vectorflow search "query" -k 5 # Limit results
vectorflow search "query" --json

# Data ingestion
vectorflow upsert doc-1 "text content"
vectorflow upsert doc-2 "text" -m '{"category": "AI"}'
vectorflow batch-upsert data.json
vectorflow batch-upsert data.json --dry-run

# Embeddings
vectorflow embed "text to embed"
vectorflow embed "text" --json
```

## Configuration

```bash
export VECTORFLOW_GATEWAY_URL=http://localhost:8080
```

Or use `--gateway-url` flag.

## Batch Upsert Format

```json
[
  {"id": "doc-1", "text": "Content here", "metadata": {"type": "article"}},
  {"id": "doc-2", "text": "More content"}
]
```
