"""Pydantic models for VectorFlow Inference Service."""

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ----- Request Models -----


class EmbeddingRequest(BaseModel):
    """Request to generate embeddings for text."""

    texts: list[str] = Field(
        ...,
        min_length=1,
        max_length=100,
        description="List of texts to generate embeddings for",
    )
    normalize: bool = Field(
        default=True,
        description="Whether to L2-normalize the embeddings",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "texts": ["What is machine learning?", "How does AI work?"],
                    "normalize": True,
                }
            ]
        }
    }


class SearchRequest(BaseModel):
    """Request for semantic search."""

    query: str = Field(
        ...,
        min_length=1,
        max_length=10000,
        description="Search query text",
    )
    top_k: int = Field(
        default=10,
        ge=1,
        le=100,
        description="Number of results to return",
    )
    namespace: str | None = Field(
        default=None,
        description="Pinecone namespace to search in",
    )
    filter: dict[str, Any] | None = Field(
        default=None,
        description="Metadata filter for search",
    )
    include_metadata: bool = Field(
        default=True,
        description="Whether to include metadata in results",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "query": "How do neural networks learn?",
                    "top_k": 5,
                    "namespace": "documentation",
                    "include_metadata": True,
                }
            ]
        }
    }


class UpsertRequest(BaseModel):
    """Request to upsert vectors to Pinecone."""

    id: str = Field(..., description="Unique identifier for the vector")
    text: str = Field(..., description="Text to generate embedding for")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Metadata to store with the vector",
    )
    namespace: str | None = Field(
        default=None,
        description="Pinecone namespace",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "id": "doc-001",
                    "text": "Machine learning is a subset of artificial intelligence.",
                    "metadata": {"source": "wiki", "category": "AI"},
                    "namespace": "documentation",
                }
            ]
        }
    }


class BatchUpsertRequest(BaseModel):
    """Request to batch upsert vectors."""

    vectors: list[UpsertRequest] = Field(
        ...,
        min_length=1,
        max_length=100,
        description="List of vectors to upsert",
    )


# ----- Response Models -----


class EmbeddingResponse(BaseModel):
    """Response containing generated embeddings."""

    embeddings: list[list[float]] = Field(
        ...,
        description="List of embedding vectors",
    )
    model: str = Field(
        ...,
        description="Model used to generate embeddings",
    )
    dimension: int = Field(
        ...,
        description="Dimension of each embedding vector",
    )
    usage: dict[str, int] = Field(
        default_factory=dict,
        description="Token usage statistics",
    )


class SearchResult(BaseModel):
    """Single search result."""

    id: str = Field(..., description="Vector ID")
    score: float = Field(..., description="Similarity score")
    metadata: dict[str, Any] | None = Field(
        default=None,
        description="Associated metadata",
    )


class SearchResponse(BaseModel):
    """Response containing search results."""

    results: list[SearchResult] = Field(
        ...,
        description="List of search results",
    )
    query: str = Field(..., description="Original query")
    total_results: int = Field(..., description="Total number of results")
    latency_ms: float = Field(..., description="Search latency in milliseconds")


class UpsertResponse(BaseModel):
    """Response for upsert operation."""

    upserted_count: int = Field(..., description="Number of vectors upserted")
    ids: list[str] = Field(..., description="IDs of upserted vectors")


class HealthResponse(BaseModel):
    """Health check response."""

    status: str = Field(..., description="Service status")
    version: str = Field(..., description="Service version")
    model_loaded: bool = Field(..., description="Whether ML model is loaded")
    pinecone_connected: bool = Field(..., description="Pinecone connection status")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow,
        description="Response timestamp",
    )


class ErrorResponse(BaseModel):
    """Error response model."""

    error: str = Field(..., description="Error type")
    message: str = Field(..., description="Error message")
    detail: str | None = Field(default=None, description="Detailed error info")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow,
        description="Error timestamp",
    )
