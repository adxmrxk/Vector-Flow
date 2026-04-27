"""Embedding service using Sentence Transformers."""

import time
from typing import Any

import numpy as np
import structlog
from sentence_transformers import SentenceTransformer
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import Settings

logger = structlog.get_logger(__name__)


class EmbeddingService:
    """Service for generating text embeddings using transformer models."""

    def __init__(self, settings: Settings) -> None:
        """Initialize the embedding service.

        Args:
            settings: Application settings
        """
        self.settings = settings
        self._model: SentenceTransformer | None = None
        self._model_loaded = False

    @property
    def is_loaded(self) -> bool:
        """Check if model is loaded."""
        return self._model_loaded

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
    )
    def load_model(self) -> None:
        """Load the sentence transformer model.

        Raises:
            RuntimeError: If model fails to load after retries
        """
        logger.info(
            "Loading embedding model",
            model=self.settings.model_name,
            device=self.settings.device,
            cache_dir=self.settings.model_cache_dir,
        )

        start_time = time.time()

        try:
            self._model = SentenceTransformer(
                self.settings.model_name,
                device=self.settings.device,
                cache_folder=self.settings.model_cache_dir,
            )

            # Set max sequence length
            self._model.max_seq_length = self.settings.max_sequence_length

            self._model_loaded = True
            load_time = time.time() - start_time

            logger.info(
                "Model loaded successfully",
                model=self.settings.model_name,
                dimension=self.settings.embedding_dimension,
                load_time_seconds=round(load_time, 2),
            )

        except Exception as e:
            logger.error(
                "Failed to load model",
                model=self.settings.model_name,
                error=str(e),
            )
            raise RuntimeError(f"Failed to load model: {e}") from e

    def _ensure_model_loaded(self) -> None:
        """Ensure model is loaded before generating embeddings."""
        if not self._model_loaded or self._model is None:
            self.load_model()

    def embed(
        self,
        texts: list[str],
        normalize: bool = True,
        show_progress: bool = False,
    ) -> dict[str, Any]:
        """Generate embeddings for a list of texts.

        Args:
            texts: List of texts to embed
            normalize: Whether to L2-normalize embeddings
            show_progress: Whether to show progress bar

        Returns:
            Dictionary containing embeddings and metadata

        Raises:
            RuntimeError: If model is not loaded
        """
        self._ensure_model_loaded()

        if self._model is None:
            raise RuntimeError("Model not loaded")

        logger.debug(
            "Generating embeddings",
            num_texts=len(texts),
            normalize=normalize,
        )

        start_time = time.time()

        # Generate embeddings
        embeddings = self._model.encode(
            texts,
            batch_size=self.settings.batch_size,
            normalize_embeddings=normalize,
            show_progress_bar=show_progress,
            convert_to_numpy=True,
        )

        # Ensure we have a numpy array
        if not isinstance(embeddings, np.ndarray):
            embeddings = np.array(embeddings)

        encode_time = time.time() - start_time

        # Calculate token count estimate (rough approximation)
        total_chars = sum(len(t) for t in texts)
        estimated_tokens = total_chars // 4  # Rough estimate

        logger.debug(
            "Embeddings generated",
            num_embeddings=len(embeddings),
            dimension=embeddings.shape[1],
            encode_time_ms=round(encode_time * 1000, 2),
        )

        return {
            "embeddings": embeddings.tolist(),
            "model": self.settings.model_name,
            "dimension": embeddings.shape[1],
            "usage": {
                "total_texts": len(texts),
                "estimated_tokens": estimated_tokens,
            },
            "latency_ms": round(encode_time * 1000, 2),
        }

    def embed_single(self, text: str, normalize: bool = True) -> list[float]:
        """Generate embedding for a single text.

        Args:
            text: Text to embed
            normalize: Whether to L2-normalize

        Returns:
            Embedding vector as list of floats
        """
        result = self.embed([text], normalize=normalize)
        return result["embeddings"][0]

    def similarity(
        self,
        query_embedding: list[float],
        candidate_embeddings: list[list[float]],
    ) -> list[float]:
        """Calculate cosine similarity between query and candidates.

        Args:
            query_embedding: Query embedding vector
            candidate_embeddings: List of candidate embedding vectors

        Returns:
            List of similarity scores
        """
        query = np.array(query_embedding)
        candidates = np.array(candidate_embeddings)

        # Normalize vectors (if not already normalized)
        query_norm = query / np.linalg.norm(query)
        candidates_norm = candidates / np.linalg.norm(candidates, axis=1, keepdims=True)

        # Calculate cosine similarity
        similarities = np.dot(candidates_norm, query_norm)

        return similarities.tolist()

    def get_model_info(self) -> dict[str, Any]:
        """Get information about the loaded model.

        Returns:
            Dictionary with model information
        """
        return {
            "model_name": self.settings.model_name,
            "dimension": self.settings.embedding_dimension,
            "max_sequence_length": self.settings.max_sequence_length,
            "device": self.settings.device,
            "loaded": self._model_loaded,
        }
