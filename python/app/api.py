"""FastAPI application and routes for VectorFlow Inference Service."""

import time
from contextlib import asynccontextmanager
from typing import Any, AsyncGenerator

import structlog
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, generate_latest

from app import __version__
from app.config import Settings, get_settings
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


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup/shutdown."""
    global embedding_service, vector_store

    settings = get_settings()

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

    logger.info("Service startup complete")

    yield

    # Shutdown
    logger.info("Shutting down VectorFlow Inference Service")


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
            ).model_dump(),
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
            ).model_dump(),
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
    async def metrics() -> str:
        """Prometheus metrics endpoint."""
        return generate_latest().decode()

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

        # Search in Pinecone
        search_result = vector_store.query(
            vector=query_embedding,
            top_k=request.top_k,
            namespace=request.namespace,
            filter=request.filter,
            include_metadata=request.include_metadata,
        )

        total_latency = (time.time() - start_time) * 1000

        return SearchResponse(
            results=[SearchResult(**r) for r in search_result["results"]],
            query=request.query,
            total_results=search_result["total_results"],
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

        # Generate embedding
        embedding = embedding_service.embed_single(request.text)

        # Upsert to Pinecone
        result = vector_store.upsert(
            vectors=[
                {
                    "id": request.id,
                    "values": embedding,
                    "metadata": request.metadata,
                }
            ],
            namespace=request.namespace,
        )

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

        # Generate embeddings for all texts
        texts = [v.text for v in request.vectors]
        embeddings_result = embedding_service.embed(texts)

        # Prepare vectors for upsert
        vectors = []
        for i, v in enumerate(request.vectors):
            vectors.append(
                {
                    "id": v.id,
                    "values": embeddings_result["embeddings"][i],
                    "metadata": v.metadata,
                }
            )

        # Upsert to Pinecone
        result = vector_store.upsert(
            vectors=vectors,
            namespace=request.vectors[0].namespace if request.vectors else None,
        )

        return UpsertResponse(
            upserted_count=result["upserted_count"],
            ids=result["ids"],
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
            return {"error": "Vector store not connected"}
        return vector_store.describe_index()

    return app


# Create default application instance
app = create_app()
