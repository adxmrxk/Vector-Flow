package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"
	"github.com/vectorflow/gateway/internal/api"
	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/service"
)

func init() { gin.SetMode(gin.TestMode) }

func testCfg() *config.Config {
	cfg := &config.Config{}
	cfg.Server.Environment = "development"
	cfg.Services.InferenceURL = "http://127.0.0.1:1"
	cfg.Services.WorkerURL = "http://127.0.0.1:1"
	cfg.Logging.Level = "info"
	return cfg
}

func testRouter(cfg *config.Config) *gin.Engine {
	return setupRouter(cfg, api.NewHandler(cfg, service.NewClient(cfg)))
}

// routeSet returns "METHOD path" for every registered route.
func routeSet(r *gin.Engine) map[string]bool {
	out := map[string]bool{}
	for _, ri := range r.Routes() {
		out[ri.Method+" "+ri.Path] = true
	}
	return out
}

// TestAllDocumentedRoutesAreRegistered pins the router against the endpoints
// the README, the CLI, the web UI and scripts/vf-health.sh all depend on.
// /v1/index in particular was called by three clients but never registered.
func TestAllDocumentedRoutesAreRegistered(t *testing.T) {
	routes := routeSet(testRouter(testCfg()))

	want := []string{
		"GET /health",
		"GET /ready",
		"GET /metrics",
		"POST /auth/register",
		"POST /auth/login",
		"POST /auth/refresh",
		"GET /auth/me",
		"GET /auth/validate",
		"POST /v1/embeddings",
		"POST /v1/search",
		"POST /v1/upsert",
		"POST /v1/upsert/batch",
		"GET /v1/model",
		"GET /v1/index",
	}
	for _, r := range want {
		if !routes[r] {
			t.Errorf("route not registered: %s", r)
		}
	}
}

func TestHealthAndMetricsArePublic(t *testing.T) {
	cfg := testCfg()
	cfg.Auth.Enabled = true // even with auth on, these must not 401
	r := testRouter(cfg)

	for _, path := range []string{"/health", "/metrics"} {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code == http.StatusUnauthorized {
			t.Errorf("%s returned 401; health and metrics must stay public", path)
		}
	}
}

func TestV1RoutesRequireAuthWhenEnabled(t *testing.T) {
	cfg := testCfg()
	cfg.Auth.Enabled = true
	r := testRouter(cfg)

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/model", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401 for /v1/* with auth enabled", w.Code)
	}
}

func TestMetricsEndpointServesPrometheusText(t *testing.T) {
	r := testRouter(testCfg())

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if ct := w.Header().Get("Content-Type"); ct == "" {
		t.Error("missing Content-Type on /metrics")
	}
}

func TestCORSPreflightShortCircuits(t *testing.T) {
	r := testRouter(testCfg())

	req := httptest.NewRequest(http.MethodOptions, "/v1/search", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("preflight status = %d, want 204", w.Code)
	}
	if w.Header().Get("Access-Control-Allow-Origin") == "" {
		t.Error("preflight response is missing Access-Control-Allow-Origin")
	}
}

func TestCORSHeadersOnNormalRequest(t *testing.T) {
	r := testRouter(testCfg())

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))

	if w.Header().Get("Access-Control-Allow-Origin") == "" {
		t.Error("missing CORS header on a normal request")
	}
}

// TestTracingMiddlewareSetsTraceHeader guards the X-Trace-ID response header
// the middleware adds on every request.
func TestTracingMiddlewareSetsTraceHeader(t *testing.T) {
	r := testRouter(testCfg())

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))

	if w.Header().Get("X-Trace-ID") == "" {
		t.Error("X-Trace-ID header not set")
	}
}

func TestUnknownRouteReturns404(t *testing.T) {
	r := testRouter(testCfg())

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/does-not-exist", nil))

	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", w.Code)
	}
}

func TestSetupLoggingAcceptsLevelsAndBadInput(t *testing.T) {
	for _, lvl := range []string{"debug", "info", "warn", "error", "nonsense"} {
		cfg := testCfg()
		cfg.Logging.Level = lvl
		setupLogging(cfg) // must not panic; bad input falls back to info
	}
	// Restore a predictable global level for any later tests.
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
}

func TestProductionUsesReleaseMode(t *testing.T) {
	defer gin.SetMode(gin.TestMode)

	cfg := testCfg()
	cfg.Server.Environment = "production"
	testRouter(cfg)

	if gin.Mode() != gin.ReleaseMode {
		t.Errorf("gin mode = %q, want release in production", gin.Mode())
	}
}
