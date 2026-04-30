"""Integration tests for VectorFlow services.

These tests verify that services can communicate with each other correctly.
Run with: pytest tests/integration/ -v

Requirements:
- All services must be running (use `make docker-up` or `make local-dev`)
- Tests use actual HTTP calls to verify service integration
"""

import os
import time
from typing import Any

import httpx
import pytest

# Service URLs (configurable via environment)
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://localhost:8080")
WORKER_URL = os.getenv("WORKER_URL", "http://localhost:8081")
INFERENCE_URL = os.getenv("INFERENCE_URL", "http://localhost:8082")

# Test timeout
TIMEOUT = 30.0


# ----- Fixtures -----


@pytest.fixture(scope="session")
def http_client() -> httpx.Client:
    """Create HTTP client for tests."""
    return httpx.Client(timeout=TIMEOUT)


@pytest.fixture(scope="session")
def async_client() -> httpx.AsyncClient:
    """Create async HTTP client for tests."""
    return httpx.AsyncClient(timeout=TIMEOUT)


def wait_for_service(url: str, max_retries: int = 30, delay: float = 1.0) -> bool:
    """Wait for a service to become healthy.

    Args:
        url: Service health endpoint URL
        max_retries: Maximum number of retry attempts
        delay: Delay between retries in seconds

    Returns:
        True if service is healthy, False otherwise
    """
    for i in range(max_retries):
        try:
            response = httpx.get(f"{url}/health", timeout=5.0)
            if response.status_code == 200:
                return True
        except httpx.RequestError:
            pass
        time.sleep(delay)
    return False


# ----- Health Check Tests -----


class TestHealthChecks:
    """Tests for service health endpoints."""

    def test_gateway_health(self, http_client: httpx.Client) -> None:
        """Test gateway health endpoint."""
        response = http_client.get(f"{GATEWAY_URL}/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] in ["healthy", "degraded"]
        assert "version" in data
        assert "environment" in data

    def test_worker_health(self, http_client: httpx.Client) -> None:
        """Test worker health endpoint."""
        response = http_client.get(f"{WORKER_URL}/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
        assert "uptime_seconds" in data

    def test_inference_health(self, http_client: httpx.Client) -> None:
        """Test inference service health endpoint."""
        response = http_client.get(f"{INFERENCE_URL}/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data

    def test_gateway_readiness(self, http_client: httpx.Client) -> None:
        """Test gateway readiness endpoint."""
        response = http_client.get(f"{GATEWAY_URL}/ready")
        assert response.status_code == 200

    def test_worker_readiness(self, http_client: httpx.Client) -> None:
        """Test worker readiness endpoint."""
        response = http_client.get(f"{WORKER_URL}/ready")
        assert response.status_code == 200

    def test_inference_readiness(self, http_client: httpx.Client) -> None:
        """Test inference readiness endpoint."""
        response = http_client.get(f"{INFERENCE_URL}/ready")
        assert response.status_code == 200


# ----- Gateway to Worker Integration Tests -----


class TestGatewayWorkerIntegration:
    """Tests for Gateway -> Worker communication."""

    def test_rerank_via_gateway(self, http_client: httpx.Client) -> None:
        """Test re-ranking through the gateway (if routed)."""
        # This test verifies the worker is accessible
        response = http_client.post(
            f"{WORKER_URL}/v1/rerank",
            json={
                "query": "machine learning",
                "results": [
                    {"id": "doc1", "score": 0.8, "metadata": {"text": "Introduction to machine learning"}},
                    {"id": "doc2", "score": 0.7, "metadata": {"text": "Deep learning neural networks"}},
                    {"id": "doc3", "score": 0.6, "metadata": {"text": "Data science basics"}},
                ],
                "top_k": 2,
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "results" in data
        assert len(data["results"]) == 2
        assert "latency_ms" in data

    def test_similarity_calculation(self, http_client: httpx.Client) -> None:
        """Test cosine similarity calculation on worker."""
        response = http_client.post(
            f"{WORKER_URL}/v1/similarity",
            json={
                "vector_a": [1.0, 0.0, 0.0],
                "vector_b": [1.0, 0.0, 0.0],
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert data["similarity"] == pytest.approx(1.0, abs=0.001)
        assert data["method"] == "cosine"

    def test_similarity_orthogonal_vectors(self, http_client: httpx.Client) -> None:
        """Test similarity of orthogonal vectors."""
        response = http_client.post(
            f"{WORKER_URL}/v1/similarity",
            json={
                "vector_a": [1.0, 0.0, 0.0],
                "vector_b": [0.0, 1.0, 0.0],
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert data["similarity"] == pytest.approx(0.0, abs=0.001)


# ----- Gateway to Inference Integration Tests -----


class TestGatewayInferenceIntegration:
    """Tests for Gateway -> Inference communication."""

    def test_embeddings_generation(self, http_client: httpx.Client) -> None:
        """Test embedding generation through inference service."""
        response = http_client.post(
            f"{INFERENCE_URL}/v1/embeddings",
            json={
                "texts": ["Hello world", "Machine learning is great"],
                "normalize": True,
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "embeddings" in data
        assert len(data["embeddings"]) == 2
        assert "dimension" in data
        assert data["dimension"] > 0

    def test_model_info(self, http_client: httpx.Client) -> None:
        """Test model info endpoint."""
        response = http_client.get(f"{INFERENCE_URL}/v1/model")
        assert response.status_code == 200

        data = response.json()
        assert "model_name" in data
        assert "dimension" in data
        assert "max_sequence_length" in data


# ----- End-to-End Flow Tests -----


class TestEndToEndFlows:
    """Tests for complete request flows through the system."""

    def test_gateway_aggregates_health(self, http_client: httpx.Client) -> None:
        """Test that gateway health reflects downstream service status."""
        response = http_client.get(f"{GATEWAY_URL}/health")
        assert response.status_code == 200

        data = response.json()
        # Gateway should report on worker and inference status
        assert "worker_status" in data or "workerStatus" in data
        assert "inference_status" in data or "inferenceStatus" in data

    def test_trace_id_propagation(self, http_client: httpx.Client) -> None:
        """Test that trace IDs are returned in response headers."""
        response = http_client.get(f"{GATEWAY_URL}/health")
        assert response.status_code == 200

        # If OpenTelemetry is enabled, X-Trace-ID should be present
        # This is optional - not all deployments have tracing enabled
        if "X-Trace-ID" in response.headers:
            trace_id = response.headers["X-Trace-ID"]
            assert len(trace_id) == 32  # Standard trace ID length


# ----- Error Handling Tests -----


class TestErrorHandling:
    """Tests for error handling across services."""

    def test_worker_invalid_similarity_dimensions(self, http_client: httpx.Client) -> None:
        """Test worker returns error for mismatched vector dimensions."""
        response = http_client.post(
            f"{WORKER_URL}/v1/similarity",
            json={
                "vector_a": [1.0, 0.0],
                "vector_b": [1.0, 0.0, 0.0],  # Different dimension
            },
        )
        assert response.status_code == 400

        data = response.json()
        assert "error" in data or "message" in data

    def test_inference_empty_texts(self, http_client: httpx.Client) -> None:
        """Test inference service handles empty text list."""
        response = http_client.post(
            f"{INFERENCE_URL}/v1/embeddings",
            json={"texts": []},
        )
        # Should return 422 (validation error) or handle gracefully
        assert response.status_code in [400, 422]

    def test_gateway_invalid_json(self, http_client: httpx.Client) -> None:
        """Test gateway handles invalid JSON gracefully."""
        response = http_client.post(
            f"{GATEWAY_URL}/v1/search",
            content="not valid json",
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code in [400, 422]


# ----- Performance Tests -----


class TestPerformance:
    """Basic performance tests for the services."""

    def test_health_check_latency(self, http_client: httpx.Client) -> None:
        """Test health check responds within acceptable time."""
        start = time.time()
        response = http_client.get(f"{GATEWAY_URL}/health")
        latency = time.time() - start

        assert response.status_code == 200
        assert latency < 1.0  # Should respond within 1 second

    def test_worker_rerank_latency(self, http_client: httpx.Client) -> None:
        """Test re-ranking responds within acceptable time."""
        start = time.time()
        response = http_client.post(
            f"{WORKER_URL}/v1/rerank",
            json={
                "query": "test query",
                "results": [
                    {"id": f"doc{i}", "score": 0.9 - i * 0.1, "metadata": {"text": f"Document {i}"}}
                    for i in range(10)
                ],
                "top_k": 5,
            },
        )
        latency = time.time() - start

        assert response.status_code == 200
        assert latency < 2.0  # Should respond within 2 seconds


# ----- Metrics Tests -----


class TestMetrics:
    """Tests for Prometheus metrics endpoints."""

    def test_gateway_metrics(self, http_client: httpx.Client) -> None:
        """Test gateway exposes Prometheus metrics."""
        response = http_client.get(f"{GATEWAY_URL}/metrics")
        assert response.status_code == 200
        # Prometheus metrics are in text format
        assert "go_" in response.text or "process_" in response.text or "vectorflow" in response.text

    def test_inference_metrics(self, http_client: httpx.Client) -> None:
        """Test inference service exposes Prometheus metrics."""
        response = http_client.get(f"{INFERENCE_URL}/metrics")
        assert response.status_code == 200
        assert "vectorflow" in response.text or "python" in response.text


# ----- Run Tests -----

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
