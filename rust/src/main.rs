//! VectorFlow Worker - High-performance computational service
//!
//! Handles heavy post-processing and re-ranking of search results.

use axum::{
    extract::{Request, State},
    http::{HeaderMap, StatusCode},
    middleware::{self, Next},
    response::{Json, Response},
    routing::{get, post},
    Router,
};
use opentelemetry::global;
use opentelemetry::propagation::Extractor;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, trace as sdktrace, Resource};
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc, time::Instant};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{info, instrument, Instrument, Level};
use tracing_opentelemetry::OpenTelemetrySpanExt;
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
    metrics: PrometheusHandle,
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

/// Prometheus scrape endpoint.
async fn metrics_handler(State(state): State<Arc<AppState>>) -> String {
    state.metrics.render()
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

    let elapsed = start.elapsed().as_secs_f64();
    metrics::counter!("vectorflow_worker_requests_total", "endpoint" => "rerank").increment(1);
    metrics::histogram!("vectorflow_worker_request_latency_seconds", "endpoint" => "rerank")
        .record(elapsed);
    metrics::counter!("vectorflow_worker_reranked_results_total").increment(results.len() as u64);

    Ok(Json(RerankResponse {
        results,
        latency_ms: elapsed * 1000.0,
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

// ----- Trace Context Propagation -----

/// Reads W3C trace headers off an incoming request.
struct HeaderExtractor<'a>(&'a HeaderMap);

impl Extractor for HeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|v| v.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|k| k.as_str()).collect()
    }
}

/// Joins the caller's trace instead of starting a new one. Without this the
/// worker's spans show up in Jaeger as separate traces, so a search cannot be
/// followed end to end.
async fn propagate_trace_context(req: Request, next: Next) -> Response {
    let parent_cx =
        global::get_text_map_propagator(|p| p.extract(&HeaderExtractor(req.headers())));

    let span = tracing::info_span!(
        "http_request",
        otel.name = %format!("{} {}", req.method(), req.uri().path()),
        http.method = %req.method(),
        http.target = %req.uri().path(),
    );
    span.set_parent(parent_cx);

    next.run(req).instrument(span).await
}

// ----- Telemetry -----

fn init_tracer(config: &AppConfig) -> Option<sdktrace::Tracer> {
    if !config.otel_enabled {
        info!("OpenTelemetry tracing disabled");
        return None;
    }

    let endpoint = config.otel_endpoint.as_ref()?;

    global::set_text_map_propagator(TraceContextPropagator::new());

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
    let tracer = init_tracer(&config);

    // Initialize tracing subscriber with OpenTelemetry layer
    let subscriber = tracing_subscriber::registry()
        .with(fmt::layer().with_target(false))
        .with(EnvFilter::from_default_env().add_directive(Level::INFO.into()));

    if let Some(tracer) = tracer {
        subscriber.with(OpenTelemetryLayer::new(tracer)).init();
    } else {
        subscriber.init();
    }

    // Explicit buckets make the exporter emit a real Prometheus histogram
    // (_bucket series). Without them it renders a summary of quantiles, which
    // histogram_quantile() cannot aggregate across instances.
    let metrics_handle = PrometheusBuilder::new()
        .set_buckets(&[
            // Re-ranking is pure CPU work measured in microseconds, so the
            // range starts well below the usual HTTP defaults.
            0.000_01, 0.000_025, 0.000_05, 0.000_1, 0.000_25, 0.000_5, 0.001, 0.005, 0.01,
            0.05, 0.1, 0.5, 1.0,
        ])
        .expect("invalid histogram buckets")
        .install_recorder()
        .expect("failed to install Prometheus recorder");

    let state = Arc::new(AppState {
        config: config.clone(),
        start_time: Instant::now(),
        metrics: metrics_handle,
    });

    // Build router
    let app = Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/metrics", get(metrics_handler))
        .route("/v1/rerank", post(rerank))
        .route("/v1/similarity", post(cosine_similarity))
        .layer(middleware::from_fn(propagate_trace_context))
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

// ----- Tests -----

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> Arc<AppState> {
        Arc::new(AppState {
            config: AppConfig::default(),
            start_time: Instant::now(),
            metrics: PrometheusBuilder::new().build_recorder().handle(),
        })
    }

    fn result(id: &str, score: f64, text: &str) -> SearchResult {
        SearchResult {
            id: id.to_string(),
            score,
            metadata: Some(serde_json::json!({ "text": text })),
        }
    }

    #[tokio::test]
    async fn cosine_identical_vectors_is_one() {
        let resp = cosine_similarity(Json(SimilarityRequest {
            vector_a: vec![1.0, 2.0, 3.0],
            vector_b: vec![1.0, 2.0, 3.0],
        }))
        .await
        .expect("should succeed");
        assert!((resp.0.similarity - 1.0).abs() < 1e-9);
        assert_eq!(resp.0.method, "cosine");
    }

    #[tokio::test]
    async fn cosine_orthogonal_vectors_is_zero() {
        let resp = cosine_similarity(Json(SimilarityRequest {
            vector_a: vec![1.0, 0.0],
            vector_b: vec![0.0, 1.0],
        }))
        .await
        .expect("should succeed");
        assert!(resp.0.similarity.abs() < 1e-9);
    }

    #[tokio::test]
    async fn cosine_opposite_vectors_is_negative_one() {
        let resp = cosine_similarity(Json(SimilarityRequest {
            vector_a: vec![1.0, 0.0],
            vector_b: vec![-1.0, 0.0],
        }))
        .await
        .expect("should succeed");
        assert!((resp.0.similarity + 1.0).abs() < 1e-9);
    }

    #[tokio::test]
    async fn cosine_zero_vector_does_not_divide_by_zero() {
        let resp = cosine_similarity(Json(SimilarityRequest {
            vector_a: vec![0.0, 0.0],
            vector_b: vec![1.0, 1.0],
        }))
        .await
        .expect("should succeed");
        assert_eq!(resp.0.similarity, 0.0);
    }

    #[tokio::test]
    async fn cosine_rejects_dimension_mismatch() {
        let err = cosine_similarity(Json(SimilarityRequest {
            vector_a: vec![1.0, 0.0, 0.0],
            vector_b: vec![1.0, 0.0],
        }))
        .await
        .expect_err("mismatched dimensions must be rejected");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn rerank_boosts_query_term_overlap() {
        // "a" starts ahead on raw score but shares no query terms; "b" overlaps
        // fully and should overtake it after the 10%-per-overlap boost.
        let resp = rerank(
            State(state()),
            Json(RerankRequest {
                query: "electric car battery".to_string(),
                results: vec![
                    result("a", 0.50, "a boat on the sea"),
                    result("b", 0.49, "electric car battery range"),
                ],
                top_k: None,
            }),
        )
        .await
        .expect("should succeed");

        let ids: Vec<&str> = resp.0.results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, vec!["b", "a"], "full-overlap result should rank first");
        assert!((resp.0.results[0].score - 0.539).abs() < 1e-6);
    }

    #[tokio::test]
    async fn rerank_truncates_to_top_k() {
        let resp = rerank(
            State(state()),
            Json(RerankRequest {
                query: "x".to_string(),
                results: vec![
                    result("a", 0.9, "one"),
                    result("b", 0.8, "two"),
                    result("c", 0.7, "three"),
                ],
                top_k: Some(2),
            }),
        )
        .await
        .expect("should succeed");
        assert_eq!(resp.0.results.len(), 2);
    }

    #[tokio::test]
    async fn rerank_handles_missing_metadata() {
        let resp = rerank(
            State(state()),
            Json(RerankRequest {
                query: "anything".to_string(),
                results: vec![SearchResult {
                    id: "no-meta".to_string(),
                    score: 0.42,
                    metadata: None,
                }],
                top_k: None,
            }),
        )
        .await
        .expect("results without metadata must not panic");
        assert_eq!(resp.0.results[0].score, 0.42);
    }
}
