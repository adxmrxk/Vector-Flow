"""Vector store service for Pinecone integration."""

import time
from typing import Any

import structlog
from pinecone import Pinecone, ServerlessSpec
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import Settings

logger = structlog.get_logger(__name__)


class VectorStoreService:
    """Service for interacting with Pinecone vector database."""

    def __init__(self, settings: Settings) -> None:
        """Initialize the vector store service.

        Args:
            settings: Application settings
        """
        self.settings = settings
        self._client: Pinecone | None = None
        self._index: Any = None
        self._connected = False

    @property
    def is_connected(self) -> bool:
        """Check if connected to Pinecone."""
        return self._connected

    def connect(self) -> None:
        """Connect to Pinecone and initialize index.

        Raises:
            RuntimeError: If connection fails
        """
        if not self.settings.pinecone_api_key:
            logger.warning(
                "Pinecone API key not configured",
                hint="Set PINECONE_API_KEY in environment",
            )
            return

        logger.info(
            "Connecting to Pinecone",
            index=self.settings.pinecone_index_name,
            environment=self.settings.pinecone_environment,
        )

        try:
            # Initialize Pinecone client
            self._client = Pinecone(api_key=self.settings.pinecone_api_key)

            # Check if index exists, create if not
            existing_indexes = [idx.name for idx in self._client.list_indexes()]

            if self.settings.pinecone_index_name not in existing_indexes:
                logger.info(
                    "Creating new Pinecone index",
                    index=self.settings.pinecone_index_name,
                    dimension=self.settings.embedding_dimension,
                )
                self._client.create_index(
                    name=self.settings.pinecone_index_name,
                    dimension=self.settings.embedding_dimension,
                    metric="cosine",
                    spec=ServerlessSpec(
                        cloud="aws",
                        region=self.settings.pinecone_environment,
                    ),
                )

            # Connect to index
            self._index = self._client.Index(self.settings.pinecone_index_name)
            self._connected = True

            logger.info(
                "Connected to Pinecone",
                index=self.settings.pinecone_index_name,
            )

        except Exception as e:
            logger.error(
                "Failed to connect to Pinecone",
                error=str(e),
            )
            raise RuntimeError(f"Pinecone connection failed: {e}") from e

    def _ensure_connected(self) -> None:
        """Ensure connected to Pinecone."""
        if not self._connected:
            self.connect()

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=5),
    )
    def upsert(
        self,
        vectors: list[dict[str, Any]],
        namespace: str | None = None,
    ) -> dict[str, Any]:
        """Upsert vectors to Pinecone.

        Args:
            vectors: List of vectors with id, values, and metadata
            namespace: Optional namespace

        Returns:
            Upsert response with count

        Raises:
            RuntimeError: If not connected or upsert fails
        """
        self._ensure_connected()

        if self._index is None:
            raise RuntimeError("Not connected to Pinecone")

        logger.debug(
            "Upserting vectors",
            count=len(vectors),
            namespace=namespace,
        )

        start_time = time.time()

        # Format vectors for Pinecone
        formatted_vectors = []
        for v in vectors:
            formatted = {
                "id": v["id"],
                "values": v["values"],
            }
            if "metadata" in v and v["metadata"]:
                formatted["metadata"] = v["metadata"]
            formatted_vectors.append(formatted)

        # Upsert in batches of 100
        batch_size = 100
        upserted_count = 0

        for i in range(0, len(formatted_vectors), batch_size):
            batch = formatted_vectors[i : i + batch_size]
            response = self._index.upsert(vectors=batch, namespace=namespace or "")
            upserted_count += response.upserted_count

        latency = time.time() - start_time

        logger.debug(
            "Vectors upserted",
            count=upserted_count,
            latency_ms=round(latency * 1000, 2),
        )

        return {
            "upserted_count": upserted_count,
            "ids": [v["id"] for v in vectors],
            "latency_ms": round(latency * 1000, 2),
        }

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=5),
    )
    def query(
        self,
        vector: list[float],
        top_k: int = 10,
        namespace: str | None = None,
        filter: dict[str, Any] | None = None,
        include_metadata: bool = True,
    ) -> dict[str, Any]:
        """Query vectors from Pinecone.

        Args:
            vector: Query vector
            top_k: Number of results to return
            namespace: Optional namespace
            filter: Optional metadata filter
            include_metadata: Whether to include metadata

        Returns:
            Query results

        Raises:
            RuntimeError: If not connected or query fails
        """
        self._ensure_connected()

        if self._index is None:
            raise RuntimeError("Not connected to Pinecone")

        logger.debug(
            "Querying vectors",
            top_k=top_k,
            namespace=namespace,
            has_filter=filter is not None,
        )

        start_time = time.time()

        response = self._index.query(
            vector=vector,
            top_k=top_k,
            namespace=namespace or "",
            filter=filter,
            include_metadata=include_metadata,
        )

        latency = time.time() - start_time

        # Format results
        results = []
        for match in response.matches:
            result = {
                "id": match.id,
                "score": match.score,
            }
            if include_metadata and match.metadata:
                result["metadata"] = match.metadata
            results.append(result)

        logger.debug(
            "Query completed",
            results_count=len(results),
            latency_ms=round(latency * 1000, 2),
        )

        return {
            "results": results,
            "total_results": len(results),
            "latency_ms": round(latency * 1000, 2),
        }

    def delete(
        self,
        ids: list[str] | None = None,
        delete_all: bool = False,
        namespace: str | None = None,
        filter: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Delete vectors from Pinecone.

        Args:
            ids: List of vector IDs to delete
            delete_all: Delete all vectors in namespace
            namespace: Optional namespace
            filter: Optional metadata filter

        Returns:
            Delete response
        """
        self._ensure_connected()

        if self._index is None:
            raise RuntimeError("Not connected to Pinecone")

        logger.info(
            "Deleting vectors",
            ids=ids,
            delete_all=delete_all,
            namespace=namespace,
        )

        if delete_all:
            self._index.delete(delete_all=True, namespace=namespace or "")
        elif ids:
            self._index.delete(ids=ids, namespace=namespace or "")
        elif filter:
            self._index.delete(filter=filter, namespace=namespace or "")

        return {"deleted": True}

    def describe_index(self) -> dict[str, Any]:
        """Get index statistics.

        Returns:
            Index statistics
        """
        self._ensure_connected()

        if self._index is None:
            return {"error": "Not connected"}

        stats = self._index.describe_index_stats()

        return {
            "dimension": stats.dimension,
            "total_vector_count": stats.total_vector_count,
            "namespaces": dict(stats.namespaces) if stats.namespaces else {},
        }
