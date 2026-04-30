"""OpenTelemetry configuration for distributed tracing."""

import os
from typing import Optional

import structlog
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.semconv.resource import ResourceAttributes

logger = structlog.get_logger(__name__)


def init_telemetry(
    service_name: str = "vectorflow-inference",
    service_version: str = "0.1.0",
) -> Optional[TracerProvider]:
    """Initialize OpenTelemetry tracing.

    Args:
        service_name: Name of the service for tracing
        service_version: Version of the service

    Returns:
        TracerProvider if initialized, None if disabled
    """
    # Check if tracing is enabled
    enabled = os.getenv("OTEL_TRACES_ENABLED", "true").lower() != "false"
    if not enabled:
        logger.info("OpenTelemetry tracing disabled")
        return None

    # Get OTLP endpoint
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        logger.info("No OTEL_EXPORTER_OTLP_ENDPOINT set, tracing disabled")
        return None

    # Ensure endpoint has /v1/traces suffix for HTTP exporter
    if not endpoint.endswith("/v1/traces"):
        endpoint = f"{endpoint}/v1/traces"

    try:
        # Create resource with service information
        resource = Resource.create({
            ResourceAttributes.SERVICE_NAME: service_name,
            ResourceAttributes.SERVICE_VERSION: service_version,
            ResourceAttributes.DEPLOYMENT_ENVIRONMENT: os.getenv("ENVIRONMENT", "development"),
        })

        # Create tracer provider
        provider = TracerProvider(resource=resource)

        # Create OTLP exporter
        exporter = OTLPSpanExporter(endpoint=endpoint)

        # Add batch processor
        processor = BatchSpanProcessor(exporter)
        provider.add_span_processor(processor)

        # Set global tracer provider
        trace.set_tracer_provider(provider)

        logger.info(
            "OpenTelemetry tracing initialized",
            service=service_name,
            endpoint=endpoint,
        )

        return provider

    except Exception as e:
        logger.error("Failed to initialize OpenTelemetry", error=str(e))
        return None


def instrument_fastapi(app) -> None:
    """Instrument FastAPI application with OpenTelemetry.

    Args:
        app: FastAPI application instance
    """
    enabled = os.getenv("OTEL_TRACES_ENABLED", "true").lower() != "false"
    if not enabled:
        return

    try:
        FastAPIInstrumentor.instrument_app(app)
        logger.info("FastAPI instrumented with OpenTelemetry")
    except Exception as e:
        logger.warning(f"Failed to instrument FastAPI: {e}")


def get_tracer(name: str = "vectorflow-inference") -> trace.Tracer:
    """Get a tracer instance.

    Args:
        name: Name for the tracer

    Returns:
        Tracer instance
    """
    return trace.get_tracer(name)


def shutdown_telemetry(provider: Optional[TracerProvider]) -> None:
    """Shutdown telemetry provider.

    Args:
        provider: TracerProvider to shutdown
    """
    if provider:
        provider.shutdown()
        logger.info("OpenTelemetry tracing shutdown complete")
