"""Pytest configuration for integration tests."""

import os
import time

import httpx
import pytest

# Service URLs
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://localhost:8080")
WORKER_URL = os.getenv("WORKER_URL", "http://localhost:8081")
INFERENCE_URL = os.getenv("INFERENCE_URL", "http://localhost:8082")


def wait_for_services(timeout: int = 120) -> bool:
    """Wait for all services to become healthy.

    Args:
        timeout: Maximum time to wait in seconds

    Returns:
        True if all services are healthy, False otherwise
    """
    services = [
        ("Gateway", f"{GATEWAY_URL}/health"),
        ("Worker", f"{WORKER_URL}/health"),
        ("Inference", f"{INFERENCE_URL}/health"),
    ]

    start_time = time.time()

    while time.time() - start_time < timeout:
        all_healthy = True

        for name, url in services:
            try:
                response = httpx.get(url, timeout=5.0)
                if response.status_code != 200:
                    all_healthy = False
                    print(f"  {name}: Not ready (status {response.status_code})")
            except httpx.RequestError as e:
                all_healthy = False
                print(f"  {name}: Not reachable ({e})")

        if all_healthy:
            return True

        time.sleep(2)

    return False


def pytest_configure(config):
    """Configure pytest markers."""
    config.addinivalue_line(
        "markers", "integration: mark test as integration test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow running"
    )


@pytest.fixture(scope="session", autouse=True)
def ensure_services_running():
    """Ensure all services are running before tests start."""
    print("\nWaiting for services to be ready...")

    if not wait_for_services(timeout=120):
        pytest.exit(
            "Services not ready. Please start services with 'make docker-up' or 'make local-dev'",
            returncode=1,
        )

    print("All services are ready!\n")


@pytest.fixture(scope="session")
def gateway_url() -> str:
    """Return gateway URL."""
    return GATEWAY_URL


@pytest.fixture(scope="session")
def worker_url() -> str:
    """Return worker URL."""
    return WORKER_URL


@pytest.fixture(scope="session")
def inference_url() -> str:
    """Return inference URL."""
    return INFERENCE_URL
