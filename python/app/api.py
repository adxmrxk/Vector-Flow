"""FastAPI application and routes for VectorFlow Inference Service."""

import time
from contextlib import asynccontextmanager
from typing import Any, AsyncGenerator

import structlog
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from opentelemetry import trace
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from app import __version__
from app.config import Settings, get_settings
from app.telemetry import init_telemetry, instrument_fastapi, shutdown_telemetry
from app.models import (
    BatchUpsertRequest,
    EmbeddingRequest,
    EmbeddingResponse,
    ErrorResponse,
    HealthResponse,
    SearchRequest,
    SearchResponse,
    SearchResult,
    UpsertRequest,
    UpsertResponse,
)
from services.embedding import EmbeddingService
from services.keyword_index import KeywordIndex
from services.vector_store import VectorStoreService

logger = structlog.get_logger(__name__)

# ----- Prometheus Metrics -----
REQUEST_COUNT = Counter(
    "vectorflow_requests_total",
    "Total requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "vectorflow_request_latency_seconds",
    "Request latency",
    ["method", "endpoint"],
)
EMBEDDING_COUNT = Counter(
    "vectorflow_embeddings_total",
    "Total embeddings generated",
)

# ----- Service Instances -----
embedding_service: EmbeddingService | None = None
vector_store: VectorStoreService | None = None
keyword_index: KeywordIndex | None = None
tracer_provider = None


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup/shutdown."""
    global embedding_service, vector_store, keyword_index, tracer_provider

    # Honour settings handed to create_app(); fall back to the cached global.
    settings = getattr(app.state, "settings", None) or get_settings()

    # Initialize OpenTelemetry tracing
    tracer_provider = init_telemetry(
        service_name="vectorflow-inference",
        service_version=__version__,
    )

    # Startup
    logger.info(
        "Starting VectorFlow Inference Service",
        version=__version__,
        environment=settings.environment,
    )

    # Initialize embedding service
    embedding_service = EmbeddingService(settings)
    embedding_service.load_model()

    # Initialize vector store (optional - only if API key provided)
    vector_store = VectorStoreService(settings)
    if settings.pinecone_api_key:
        try:
            vector_store.connect()
        except Exception as e:
            logger.warning(f"Failed to connect to Pinecone: {e}")

    # Initialize the keyword (BM25) side of hybrid search. Purely additive:
    # an empty path disables it and search falls back to dense-only.
    if settings.keyword_index_path:
        keyword_index = KeywordIndex(settings.keyword_index_path)

    logger.info("Service startup complete")

    yield

    # Shutdown
    logger.info("Shutting down VectorFlow Inference Service")
    shutdown_telemetry(tracer_provider)


def _build_chunk_vectors(
    doc_id: str,
    chunks: list[str],
    embeddings: list[list[float]],
    metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    """Turn a document's chunks into Pinecone vector dicts.

    A document that fits in one chunk keeps its original id and metadata
    unchanged, so nothing about the single-chunk case changes. A document
    split into multiple chunks gets one vector per chunk, each tagged with
    parent_id/chunk_index/chunk_count so search results can be deduplicated
    back to the parent document.
    """
    if len(chunks) == 1:
        return [{"id": doc_id, "values": embeddings[0], "metadata": metadata}]

    vectors = []
    for i, embedding in enumerate(embeddings):
        chunk_metadata = dict(metadata)
        chunk_metadata["parent_id"] = doc_id
        chunk_metadata["chunk_index"] = i
        chunk_metadata["chunk_count"] = len(chunks)
        vectors.append(
            {
                "id": f"{doc_id}#chunk{i}",
                "values": embedding,
                "metadata": chunk_metadata,
            }
        )
    return vectors


def _reciprocal_rank_fusion(
    dense_results: list[dict[str, Any]],
    keyword_results: list[dict[str, Any]],
    rrf_k: int = 60,
) -> list[dict[str, Any]]:
    """Fuse dense (cosine) and keyword (BM25) rankings into one ranking.

    Reciprocal Rank Fusion scores each document by 1/(rrf_k + rank) summed
    across every ranking it appears in, which combines two incomparable
    score scales (cosine similarity vs. BM25) using only rank position. A
    hit found by both rankers outranks one found by either alone. This
    replaces each result's cosine-similarity score with its fusion score,
    which callers should treat as a ranking signal, not a similarity value.
    """
    scores: dict[str, float] = {}
    info: dict[str, dict[str, Any]] = {}

    for rank, result in enumerate(dense_results, start=1):
        scores[result["id"]] = scores.get(result["id"], 0.0) + 1.0 / (rrf_k + rank)
        info.setdefault(result["id"], result)

    for rank, result in enumerate(keyword_results, start=1):
        scores[result["id"]] = scores.get(result["id"], 0.0) + 1.0 / (rrf_k + rank)
        info.setdefault(result["id"], result)

    fused = []
    for doc_id, score in scores.items():
        entry = dict(info[doc_id])
        entry["score"] = score
        fused.append(entry)

    fused.sort(key=lambda r: r["score"], reverse=True)
    return fused


def _dedupe_by_parent(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Collapse multiple chunk hits from the same document to its best hit.

    Without this, a single long document indexed as N chunks could occupy N
    slots in the top-k results, crowding out other documents entirely.
    """
    best: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for result in results:
        metadata = result.get("metadata") or {}
        key = metadata.get("parent_id") or result["id"]
        existing = best.get(key)
        if existing is None:
            best[key] = result
            order.append(key)
        elif result["score"] > existing["score"]:
            best[key] = result
    return [best[key] for key in order]


def create_app(settings: Settings | None = None) -> FastAPI:
    """Create and configure FastAPI application.

    Args:
        settings: Optional settings override

    Returns:
        Configured FastAPI application
    """
    if settings is None:
        settings = get_settings()

    app = FastAPI(
        title="VectorFlow Inference Service",
        description="Semantic search engine powered by transformer embeddings",
        version=__version__,
        docs_url="/docs" if not settings.is_production else None,
        redoc_url="/redoc" if not settings.is_production else None,
        lifespan=lifespan,
    )

    app.state.settings = settings

    # ----- OpenTelemetry Instrumentation -----
    instrument_fastapi(app)

    # ----- CORS Middleware -----
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"] if not settings.is_production else [],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ----- Request Logging Middleware -----
    @app.middleware("http")
    async def log_requests(request: Request, call_next: Any) -> Any:
        start_time = time.time()

        response = await call_next(request)

        latency = time.time() - start_time

        # Record metrics
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.url.path,
            status=response.status_code,
        ).inc()
        REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=request.url.path,
        ).observe(latency)

        logger.info(
            "Request completed",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            latency_ms=round(latency * 1000, 2),
        )

        return response

    # ----- Exception Handlers -----
    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=ErrorResponse(
                error=exc.__class__.__name__,
                message=exc.detail,
            ).model_dump(mode="json"),
        )

    @app.exception_handler(Exception)
    async def general_exception_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        logger.error("Unhandled exception", error=str(exc), exc_info=True)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=ErrorResponse(
                error="InternalServerError",
                message="An unexpected error occurred",
                detail=str(exc) if not settings.is_production else None,
            ).model_dump(mode="json"),
        )

    # ----- Health Endpoints -----
    @app.get("/health", response_model=HealthResponse, tags=["Health"])
    async def health_check() -> HealthResponse:
        """Health check endpoint for liveness probe."""
        return HealthResponse(
            status="healthy",
            version=__version__,
            model_loaded=embedding_service.is_loaded if embedding_service else False,
            pinecone_connected=vector_store.is_connected if vector_store else False,
        )

    @app.get("/ready", tags=["Health"])
    async def readiness_check() -> dict[str, str]:
        """Readiness check endpoint."""
        if not embedding_service or not embedding_service.is_loaded:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Model not loaded",
            )
        return {"status": "ready"}

    @app.get("/metrics", tags=["Health"])
    async def metrics() -> Response:
        """Prometheus metrics endpoint.

        Must be served as Prometheus text format; returning a bare `str` makes
        FastAPI serialize it as application/json, which scrapers reject.
        """
        return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

    # ----- Embedding Endpoints -----
    @app.post(
        "/v1/embeddings",
        response_model=EmbeddingResponse,
        tags=["Embeddings"],
    )
    async def create_embeddings(request: EmbeddingRequest) -> EmbeddingResponse:
        """Generate embeddings for input texts."""
        if not embedding_service or not embedding_service.is_loaded:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Embedding model not loaded",
            )

        result = embedding_service.embed(
            texts=request.texts,
            normalize=request.normalize,
        )

        EMBEDDING_COUNT.inc(len(request.texts))

        return EmbeddingResponse(
            embeddings=result["embeddings"],
            model=result["model"],
            dimension=result["dimension"],
            usage=result["usage"],
        )

    # ----- Search Endpoints -----
    @app.post(
        "/v1/search",
        response_model=SearchResponse,
        tags=["Search"],
    )
    async def semantic_search(request: SearchRequest) -> SearchResponse:
        """Perform semantic search."""
        if not embedding_service or not embedding_service.is_loaded:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Embedding model not loaded",
            )

        if not vector_store or not vector_store.is_connected:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Vector store not connected",
            )

        start_time = time.time()

        # Generate query embedding
        query_embedding = embedding_service.embed_single(request.query)

        # Fetch a larger candidate pool than top_k so fusing in keyword hits
        # (which may not overlap with the dense pool at all) has something to
        # work with, then truncate to top_k after fusing and deduping.
        retrieval_k = min(max(request.top_k * 4, 20), 100)

        # Search in Pinecone (dense/semantic side)
        search_result = vector_store.query(
            vector=query_embedding,
            top_k=retrieval_k,
            namespace=request.namespace,
            filter=request.filter,
            include_metadata=request.include_metadata,
        )

        # Search the keyword (BM25) side. Hybrid search exists specifically
        # for exact-match queries -- product IDs, error codes, rare proper
        # nouns -- that cosine similarity has no notion of matching literally.
        keyword_hits = (
            keyword_index.search(request.query, request.namespace, limit=retrieval_k)
            if keyword_index
            else []
        )

        # Only fuse when the keyword side actually found something: fusing
        # unconditionally would replace every dense-only query's cosine
        # similarity score with an RRF rank score for no benefit.
        if keyword_hits:
            fused_results = _reciprocal_rank_fusion(search_result["results"], keyword_hits)
        else:
            fused_results = search_result["results"]

        # A document split into chunks at upsert time can otherwise occupy
        # several of the top_k slots with itself; collapse to its best chunk.
        deduped_results = _dedupe_by_parent(fused_results)[: request.top_k]

        total_latency = (time.time() - start_time) * 1000

        return SearchResponse(
            results=[SearchResult(**r) for r in deduped_results],
            query=request.query,
            total_results=len(deduped_results),
            latency_ms=round(total_latency, 2),
        )

    # ----- Upsert Endpoints -----
    @app.post(
        "/v1/upsert",
        response_model=UpsertResponse,
        tags=["Vectors"],
    )
    async def upsert_vector(request: UpsertRequest) -> UpsertResponse:
        """Upsert a single vector."""
        if not embedding_service or not embedding_service.is_loaded:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Embedding model not loaded",
            )

        if not vector_store or not vector_store.is_connected:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Vector store not connected",
            )

        # Split long text into overlapping windows first: the model silently
        # truncates anything past its max sequence length, so without this a
        # long document would lose everything past the first ~512 tokens.
        chunks = embedding_service.chunk_text(request.text)
        embeddings = embedding_service.embed(chunks)["embeddings"]

        vectors = _build_chunk_vectors(request.id, chunks, embeddings, request.metadata)

        # Upsert to Pinecone
        result = vector_store.upsert(
            vectors=vectors,
            namespace=request.namespace,
        )

        # Index the same chunks into the keyword (BM25) side of hybrid search.
        if keyword_index:
            for chunk, vector in zip(chunks, vectors, strict=True):
                keyword_index.upsert(vector["id"], request.namespace, chunk, vector["metadata"])

        return UpsertResponse(
            upserted_count=result["upserted_count"],
            ids=result["ids"],
        )

    @app.post(
        "/v1/upsert/batch",
        response_model=UpsertResponse,
        tags=["Vectors"],
    )
    async def batch_upsert(request: BatchUpsertRequest) -> UpsertResponse:
        """Batch upsert vectors."""
        if not embedding_service or not embedding_service.is_loaded:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Embedding model not loaded",
            )

        if not vector_store or not vector_store.is_connected:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Vector store not connected",
            )

        # Chunk every document first, then embed every resulting chunk across
        # the whole batch in a single call. Calling embed() once per document
        # gives up the model's internal batching (measured 6x slower for 100
        # short documents: ~97 docs/sec one-at-a-time vs ~595 docs/sec batched).
        per_doc_chunks = [embedding_service.chunk_text(v.text) for v in request.vectors]
        all_chunks = [chunk for chunks in per_doc_chunks for chunk in chunks]
        all_embeddings = embedding_service.embed(all_chunks)["embeddings"] if all_chunks else []

        # Group the resulting vectors by namespace: Pinecone's upsert takes
        # one namespace per call, and a batch can legitimately contain
        # vectors bound for different namespaces (the previous code silently
        # used only the first vector's namespace for the entire batch,
        # dropping the rest into the wrong place).
        vectors_by_namespace: dict[str | None, list[dict[str, Any]]] = {}
        keyword_entries: list[tuple[str, str | None, str, dict[str, Any]]] = []
        offset = 0
        for v, chunks in zip(request.vectors, per_doc_chunks, strict=True):
            doc_embeddings = all_embeddings[offset : offset + len(chunks)]
            offset += len(chunks)

            doc_vectors = _build_chunk_vectors(v.id, chunks, doc_embeddings, v.metadata)
            vectors_by_namespace.setdefault(v.namespace, []).extend(doc_vectors)

            for chunk, vector in zip(chunks, doc_vectors, strict=True):
                keyword_entries.append((vector["id"], v.namespace, chunk, vector["metadata"]))

        if keyword_index and keyword_entries:
            keyword_index.upsert_many(keyword_entries)

        upserted_count = 0
        ids: list[str] = []
        for namespace, vectors in vectors_by_namespace.items():
            result = vector_store.upsert(vectors=vectors, namespace=namespace)
            upserted_count += result["upserted_count"]
            ids.extend(result["ids"])

        return UpsertResponse(
            upserted_count=upserted_count,
            ids=ids,
        )

    # ----- Info Endpoints -----
    @app.get("/v1/model", tags=["Info"])
    async def model_info() -> dict[str, Any]:
        """Get model information."""
        if not embedding_service:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Service not initialized",
            )
        return embedding_service.get_model_info()

    @app.get("/v1/index", tags=["Info"])
    async def index_info() -> dict[str, Any]:
        """Get vector index information."""
        if not vector_store or not vector_store.is_connected:
            # Returning a 200 with an error body made callers decode zeros and
            # report "0 vectors" for a store that is simply not connected.
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Vector store not connected",
            )
        return vector_store.describe_index()

    return app


# Create default application instance
app = create_app()
