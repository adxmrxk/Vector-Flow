from __future__ import annotations

import os
from typing import Any

import httpx
from pydantic import BaseModel


class SearchResult(BaseModel):
    """Single search result."""
    id: str
    score: float
    metadata: dict[str, Any] | None = None


class SearchResponse(BaseModel):
    """Search response from API."""
    results: list[SearchResult]
    latency_ms: float


class HealthStatus(BaseModel):
    """Service health status."""
    service: str
    status: str
    version: str | None = None
    details: dict[str, Any] | None = None


class ModelInfo(BaseModel):
    """Model information."""
    name: str
    dimension: int
    max_sequence_length: int
    device: str


class IndexStats(BaseModel):
    """Vector index statistics."""
    total_vectors: int
    dimension: int
    namespaces: dict[str, int] | None = None


class VectorFlowClient:
    """Client for VectorFlow API."""

    def __init__(
        self,
        gateway_url: str | None = None,
        timeout: float = 30.0,
    ):
        self.gateway_url = gateway_url or os.getenv(
            "VECTORFLOW_GATEWAY_URL", "http://localhost:8080"
        )
        self.timeout = timeout
        self._client = httpx.Client(
            base_url=self.gateway_url,
            timeout=timeout,
            headers={"Content-Type": "application/json"},
        )

    def close(self) -> None:
        """Close the HTTP client."""
        self._client.close()

    def __enter__(self) -> VectorFlowClient:
        return self

    def __exit__(self, *args: Any) -> None:
        self.close()

    
    def health(self) -> HealthStatus:
        """Check gateway health."""
        resp = self._client.get("/health")
        resp.raise_for_status()
        data = resp.json()
        return HealthStatus(
            service="gateway",
            status=data.get("status", "healthy"),
            version=data.get("version"),
            details=data,
        )

    def ready(self) -> bool:
        """Check if all services are ready."""
        try:
            resp = self._client.get("/ready")
            return resp.status_code == 200
        except httpx.RequestError:
            return False

    def check_all_services(self) -> list[HealthStatus]:
        """Check health of all services."""
        services = []

        # Gateway
        try:
            resp = self._client.get("/health")
            services.append(HealthStatus(
                service="gateway",
                status="healthy" if resp.status_code == 200 else "unhealthy",
                details=resp.json() if resp.status_code == 200 else None,
            ))
        except httpx.RequestError as e:
            services.append(HealthStatus(
                service="gateway",
                status="unreachable",
                details={"error": str(e)},
            ))

        # Readiness (checks downstream services)
        try:
            resp = self._client.get("/ready")
            services.append(HealthStatus(
                service="all-dependencies",
                status="ready" if resp.status_code == 200 else "not-ready",
                details=resp.json() if resp.status_code == 200 else None,
            ))
        except httpx.RequestError as e:
            services.append(HealthStatus(
                service="all-dependencies",
                status="unreachable",
                details={"error": str(e)},
            ))

        return services

    
    def search(
        self,
        query: str,
        top_k: int = 10,
        namespace: str | None = None,
        filter_metadata: dict[str, Any] | None = None,
    ) -> SearchResponse:
        """Perform semantic search."""
        payload: dict[str, Any] = {
            "query": query,
            "topK": top_k,
            "includeMetadata": True,
        }
        if namespace:
            payload["namespace"] = namespace
        if filter_metadata:
            payload["filter"] = filter_metadata

        resp = self._client.post("/v1/search", json=payload)
        resp.raise_for_status()
        data = resp.json()

        results = [
            SearchResult(
                id=r["id"],
                score=r["score"],
                metadata=r.get("metadata"),
            )
            for r in data.get("results", [])
        ]

        return SearchResponse(
            results=results,
            latency_ms=data.get("latencyMs", 0),
        )

    
    def embed(
        self,
        texts: list[str],
        normalize: bool = True,
    ) -> list[list[float]]:
        """Generate embeddings for texts."""
        resp = self._client.post(
            "/v1/embeddings",
            json={"texts": texts, "normalize": normalize},
        )
        resp.raise_for_status()
        return resp.json().get("embeddings", [])

    
    def upsert(
        self,
        id: str,
        text: str,
        metadata: dict[str, Any] | None = None,
        namespace: str | None = None,
    ) -> str:
        """Upsert a single vector."""
        payload: dict[str, Any] = {"id": id, "text": text}
        if metadata:
            payload["metadata"] = metadata
        if namespace:
            payload["namespace"] = namespace

        resp = self._client.post("/v1/upsert", json=payload)
        resp.raise_for_status()
        return resp.json().get("id", id)

    def upsert_batch(
        self,
        vectors: list[dict[str, Any]],
        namespace: str | None = None,
    ) -> int:
        """Batch upsert vectors."""
        payload: dict[str, Any] = {"vectors": vectors}
        if namespace:
            payload["namespace"] = namespace

        resp = self._client.post("/v1/upsert/batch", json=payload)
        resp.raise_for_status()
        return resp.json().get("upsertedCount", len(vectors))

    
    def model_info(self) -> ModelInfo:
        """Get loaded model information."""
        resp = self._client.get("/v1/model")
        resp.raise_for_status()
        data = resp.json()
        return ModelInfo(
            name=data["name"],
            dimension=data["dimension"],
            max_sequence_length=data["maxSequenceLength"],
            device=data["device"],
        )

    def index_stats(self) -> IndexStats:
        """Get vector index statistics."""
        resp = self._client.get("/v1/index")
        resp.raise_for_status()
        data = resp.json()
        return IndexStats(
            total_vectors=data.get("totalVectors", 0),
            dimension=data.get("dimension", 0),
            namespaces=data.get("namespaces"),
        )
