package metrics

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func init() { gin.SetMode(gin.TestMode) }

// scrape renders the default registry the way /metrics does.
func scrape(t *testing.T) string {
	t.Helper()
	w := httptest.NewRecorder()
	promhttp.Handler().ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	return w.Body.String()
}

func TestMiddlewareRecordsRequests(t *testing.T) {
	engine := gin.New()
	engine.Use(Middleware())
	engine.GET("/v1/thing", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/thing", nil))

	body := scrape(t)
	if !strings.Contains(body, "vectorflow_gateway_requests_total") {
		t.Fatal("request counter missing from /metrics output")
	}
	if !strings.Contains(body, `endpoint="/v1/thing"`) {
		t.Errorf("expected the matched route as a label; got:\n%s", firstLines(body, 20))
	}
	if !strings.Contains(body, "vectorflow_gateway_request_latency_seconds") {
		t.Error("latency histogram missing")
	}
}

// TestMiddlewareUsesRouteNotRawPath keeps metric cardinality bounded: an
// unmatched path must not become its own label value.
func TestMiddlewareUsesRouteNotRawPath(t *testing.T) {
	engine := gin.New()
	engine.Use(Middleware())

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/no/such/route/12345", nil))

	body := scrape(t)
	if strings.Contains(body, "/no/such/route/12345") {
		t.Error("raw unmatched path leaked into metric labels")
	}
	if !strings.Contains(body, `endpoint="unmatched"`) {
		t.Error(`expected endpoint="unmatched" for an unrouted request`)
	}
}

func TestObserveDownstreamRecordsSuccess(t *testing.T) {
	ObserveDownstream("inference", "unit_success", time.Now(), nil)

	body := scrape(t)
	if !strings.Contains(body, `operation="unit_success"`) {
		t.Error("downstream latency not recorded")
	}
}

func TestObserveDownstreamCountsErrors(t *testing.T) {
	ObserveDownstream("worker", "unit_failure", time.Now(), errors.New("boom"))

	body := scrape(t)
	if !strings.Contains(body, "vectorflow_gateway_downstream_errors_total") {
		t.Fatal("downstream error counter missing")
	}
	if !strings.Contains(body, `operation="unit_failure"`) {
		t.Error("failed operation not labelled")
	}
}

func firstLines(s string, n int) string {
	parts := strings.SplitN(s, "\n", n+1)
	if len(parts) > n {
		parts = parts[:n]
	}
	return strings.Join(parts, "\n")
}
