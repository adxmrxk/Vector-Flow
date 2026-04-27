# =========================
# VectorFlow Inference Service Dockerfile
# =========================
# Multi-stage build for optimized production image

# ----- Stage 1: Builder -----
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ----- Stage 2: Runtime -----
FROM python:3.11-slim as runtime

# Labels
LABEL maintainer="VectorFlow Team"
LABEL description="VectorFlow ML Inference Service"
LABEL version="0.1.0"

# Create non-root user for security
RUN groupadd -r vectorflow && useradd -r -g vectorflow vectorflow

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy wheels from builder and install
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir /wheels/* && \
    rm -rf /wheels

# Copy application code
COPY --chown=vectorflow:vectorflow app/ ./app/
COPY --chown=vectorflow:vectorflow services/ ./services/

# Create model cache directory
RUN mkdir -p /app/models && chown -R vectorflow:vectorflow /app/models

# Switch to non-root user
USER vectorflow

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    INFERENCE_HOST=0.0.0.0 \
    PYTHON_INFERENCE_PORT=8082 \
    MODEL_CACHE_DIR=/app/models

# Expose port
EXPOSE 8082

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8082/health || exit 1

# Run the service
CMD ["python", "-m", "app.main"]
