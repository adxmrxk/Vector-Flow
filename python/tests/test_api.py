"""Tests for VectorFlow Inference API."""

import pytest
from fastapi.testclient import TestClient

from app.api import create_app
from app.config import Settings


@pytest.fixture
def test_settings() -> Settings:
    """Create test settings."""
    return Settings(
        environment="development",
        debug=True,
        model_name="sentence-transformers/all-MiniLM-L6-v2",
        model_cache_dir="./test_models",
        pinecone_api_key="",  # Disable Pinecone for tests
    )


@pytest.fixture
def client(test_settings: Settings) -> TestClient:
    """Create test client."""
    app = create_app(test_settings)
    return TestClient(app)


class TestHealthEndpoints:
    """Tests for health check endpoints."""

    def test_health_check(self, client: TestClient) -> None:
        """Test health endpoint returns healthy status."""
        response = client.get("/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
        assert "model_loaded" in data
        assert "pinecone_connected" in data

    def test_readiness_check_when_ready(self, client: TestClient) -> None:
        """Test readiness endpoint when service is ready."""
        response = client.get("/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "ready"

    def test_metrics_endpoint(self, client: TestClient) -> None:
        """Test Prometheus metrics endpoint."""
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "vectorflow_requests_total" in response.text


class TestEmbeddingEndpoints:
    """Tests for embedding endpoints."""

    def test_create_embeddings_single(self, client: TestClient) -> None:
        """Test creating embedding for single text."""
        response = client.post(
            "/v1/embeddings",
            json={"texts": ["Hello, world!"], "normalize": True},
        )
        assert response.status_code == 200

        data = response.json()
        assert "embeddings" in data
        assert len(data["embeddings"]) == 1
        assert data["dimension"] == 384  # MiniLM dimension
        assert "model" in data

    def test_create_embeddings_batch(self, client: TestClient) -> None:
        """Test creating embeddings for multiple texts."""
        texts = [
            "What is machine learning?",
            "How does artificial intelligence work?",
            "Deep learning neural networks",
        ]
        response = client.post(
            "/v1/embeddings",
            json={"texts": texts, "normalize": True},
        )
        assert response.status_code == 200

        data = response.json()
        assert len(data["embeddings"]) == 3
        assert data["usage"]["total_texts"] == 3

    def test_create_embeddings_validation_error(self, client: TestClient) -> None:
        """Test validation error for empty texts."""
        response = client.post(
            "/v1/embeddings",
            json={"texts": [], "normalize": True},
        )
        assert response.status_code == 422  # Validation error


class TestModelInfo:
    """Tests for model info endpoints."""

    def test_get_model_info(self, client: TestClient) -> None:
        """Test getting model information."""
        response = client.get("/v1/model")
        assert response.status_code == 200

        data = response.json()
        assert "model_name" in data
        assert "dimension" in data
        assert "max_sequence_length" in data
        assert data["loaded"] is True


class TestSearchEndpoints:
    """Tests for search endpoints (requires Pinecone)."""

    def test_search_without_pinecone(self, client: TestClient) -> None:
        """Test search returns error when Pinecone not connected."""
        response = client.post(
            "/v1/search",
            json={"query": "test query", "top_k": 5},
        )
        # Should fail because Pinecone is not configured
        assert response.status_code == 503
