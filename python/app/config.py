"""Configuration management for VectorFlow Inference Service."""

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings with environment variable support."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ----- Application -----
    app_name: str = "VectorFlow Inference Service"
    environment: Literal["development", "staging", "production"] = "development"
    debug: bool = False
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"

    # ----- Server -----
    host: str = Field(default="0.0.0.0", alias="INFERENCE_HOST")
    port: int = Field(default=8082, alias="PYTHON_INFERENCE_PORT")
    workers: int = 1

    # ----- ML Model -----
    model_name: str = "sentence-transformers/all-MiniLM-L6-v2"
    model_cache_dir: str = "./models"
    batch_size: int = 32
    max_sequence_length: int = 512
    device: Literal["cpu", "cuda", "mps"] = "cpu"

    # ----- Pinecone -----
    pinecone_api_key: str = ""
    pinecone_environment: str = "us-east-1"
    pinecone_index_name: str = "vectorflow-index"

    # ----- Service URLs -----
    worker_service_url: str = "http://localhost:8081"
    gateway_service_url: str = "http://localhost:8080"

    # ----- Performance -----
    request_timeout: float = 30.0
    max_concurrent_requests: int = 100

    # ----- Monitoring -----
    prometheus_enabled: bool = True
    prometheus_port: int = 9090

    @property
    def is_production(self) -> bool:
        """Check if running in production."""
        return self.environment == "production"

    @property
    def embedding_dimension(self) -> int:
        """Get embedding dimension based on model.

        Common dimensions:
        - all-MiniLM-L6-v2: 384
        - all-mpnet-base-v2: 768
        - text-embedding-ada-002: 1536
        """
        model_dimensions = {
            "sentence-transformers/all-MiniLM-L6-v2": 384,
            "sentence-transformers/all-mpnet-base-v2": 768,
            "sentence-transformers/paraphrase-MiniLM-L6-v2": 384,
        }
        return model_dimensions.get(self.model_name, 384)


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
