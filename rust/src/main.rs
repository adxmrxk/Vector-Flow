//! VectorFlow Worker - High-performance computational service
//!
//! Handles heavy post-processing and re-ranking of search results.

use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use opentelemetry::global;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, trace as sdktrace, Resource};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc, time::Instant};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{info, instrument, Level};
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

// ----- Configuration -----

#[derive(Debug, Clone)]
struct AppConfig {
    host: String,
    port: u16,
    environment: String,
    otel_endpoint: Option<String>,
    otel_enabled: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            host: std::env::var("WORKER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: std::env::var("RUST_WORKER_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8081),
            environment: std::env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
            otel_endpoint: std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok(),
            otel_enabled: std::env::var("OTEL_TRACES_ENABLED")
                .map(|v| v != "false")
                .unwrap_or(true),
        }
    }
}

// ----- State -----

#[derive(Clone)]
struct AppState {
    config: AppConfig,
    start_time: Instant,
}

// ----- Models -----

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    environment: String,
    uptime_seconds: u64,
}

#[derive(Debug, Deserialize)]
struct RerankRequest {
    query: String,
    results: Vec<SearchResult>,
    top_k: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SearchResult {
    id: String,
    score: f64,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct RerankResponse {
    results: Vec<SearchResult>,
    latency_ms: f64,
}

#[derive(Debug, Deserialize)]
struct SimilarityRequest {
    vector_a: Vec<f64>,
    vector_b: Vec<f64>,
}

#[derive(Debug, Serialize)]
struct SimilarityResponse {
    similarity: f64,
    method: String,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
    message: String,
}

// ----- Handlers -----

#[instrument(skip(state))]
async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        environment: state.config.environment.clone(),
        uptime_seconds: state.start_time.elapsed().as_secs(),
    })
}

#[instrument]
async fn ready() -> Json<serde_json::Value> {
    Json(serde_json::json!({"status": "ready"}))
}

/// Re-rank search results using a simple scoring adjustment
#[instrument(skip(_state, req), fields(query = %req.query, results_count = req.results.len()))]
async fn rerank(
    State(_state): State<Arc<AppState>>,
    Json(req): Json<RerankRequest>,
) -> Result<Json<RerankResponse>, (StatusCode, Json<ErrorResponse>)> {
    let start = Instant::now();
    let top_k = req.top_k.unwrap_or(10);

    // Simple re-ranking: boost scores based on query term overlap
    let query_lower = req.query.to_lowercase();
    let query_terms: Vec<&str> = query_lower.split_whitespace().collect();

    let mut results = req.results;
    for result in &mut results {
        if let Some(meta) = &result.metadata {
            if let Some(text) = meta.get("text").and_then(|t| t.as_str()) {
                let text_lower = text.to_lowercase();
                let overlap: f64 = query_terms
                    .iter()
                    .filter(|term| text_lower.contains(*term))
                    .count() as f64
                    / query_terms.len().max(1) as f64;
                result.score = result.score * (1.0 + overlap * 0.1);
            }
        }
    }

    // Sort by adjusted score
    results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    results.truncate(top_k);

    Ok(Json(RerankResponse {
        results,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
    }))
}

/// Calculate cosine similarity between two vectors
#[instrument(skip(req), fields(vector_dim = req.vector_a.len()))]
async fn cosine_similarity(
    Json(req): Json<SimilarityRequest>,
) -> Result<Json<SimilarityResponse>, (StatusCode, Json<ErrorResponse>)> {
    if req.vector_a.len() != req.vector_b.len() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "ValidationError".to_string(),
                message: "Vectors must have the same dimension".to_string(),
            }),
        ));
    }

    let dot_product: f64 = req.vector_a.iter().zip(&req.vector_b).map(|(a, b)| a * b).sum();
    let norm_a: f64 = req.vector_a.iter().map(|x| x * x).sum::<f64>().sqrt();
    let norm_b: f64 = req.vector_b.iter().map(|x| x * x).sum::<f64>().sqrt();

    let similarity = if norm_a > 0.0 && norm_b > 0.0 {
        dot_product / (norm_a * norm_b)
    } else {
        0.0
    };

    Ok(Json(SimilarityResponse {
        similarity,
        method: "cosine".to_string(),
    }))
}

// ----- Telemetry -----

fn init_tracer(config: &AppConfig) -> Option<sdktrace::TracerProvider> {
    if !config.otel_enabled {
        info!("OpenTelemetry tracing disabled");
        return None;
    }

    let endpoint = config.otel_endpoint.as_ref()?;

    let exporter = opentelemetry_otlp::new_exporter()
        .http()
        .with_endpoint(endpoint);

    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(exporter)
        .with_trace_config(
            sdktrace::config().with_resource(Resource::new(vec![
                opentelemetry::KeyValue::new("service.name", "vectorflow-worker"),
                opentelemetry::KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
            ])),
        )
        .install_batch(runtime::Tokio)
        .ok()?;

    info!("OpenTelemetry tracing initialized with endpoint: {}", endpoint);
    Some(tracer)
}

// ----- Main -----

#[tokio::main]
async fn main() {
    let config = AppConfig::default();

    // Initialize OpenTelemetry tracer
    let _tracer = init_tracer(&config);

    // Initialize tracing subscriber with OpenTelemetry layer
    let subscriber = tracing_subscriber::registry()
        .with(fmt::layer().with_target(false))
        .with(EnvFilter::from_default_env().add_directive(Level::INFO.into()));

    if config.otel_enabled && config.otel_endpoint.is_some() {
        let tracer = global::tracer("vectorflow-worker");
        subscriber.with(OpenTelemetryLayer::new(tracer)).init();
    } else {
        subscriber.init();
    }

    let state = Arc::new(AppState {
        config: config.clone(),
        start_time: Instant::now(),
    });

    // Build router
    let app = Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/v1/rerank", post(rerank))
        .route("/v1/similarity", post(cosine_similarity))
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .expect("Invalid address");

    info!("VectorFlow Worker listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();

    // Shutdown tracer on exit
    global::shutdown_tracer_provider();
}
