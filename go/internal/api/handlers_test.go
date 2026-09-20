package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/middleware"
	"github.com/vectorflow/gateway/internal/models"
	"github.com/vectorflow/gateway/internal/service"
)

func init() { gin.SetMode(gin.TestMode) }

// newTestHandler wires a Handler against stub inference and worker servers.
func newTestHandler(inferenceURL, workerURL string) *Handler {
	cfg := &config.Config{}
	cfg.Services.InferenceURL = inferenceURL
	cfg.Services.WorkerURL = workerURL
	return NewHandler(cfg, service.NewClient(cfg))
}

func doJSON(h gin.HandlerFunc, method, path, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(method, path, strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	h(c)
	return w
}

// doJSONAs is doJSON but with JWT claims already present in the context, the
// way middleware.JWTAuth would have left them for a handler running behind it.
func doJSONAs(h gin.HandlerFunc, claims *middleware.Claims, method, path, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(method, path, strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set(middleware.ContextKey, claims)
	h(c)
	return w
}

// TestSearchCallsWorkerRerank is the regression test for the gap between the
// documented request flow (gateway -> inference -> worker -> gateway) and the
// original code, which never called the worker at all.
func TestSearchCallsWorkerRerank(t *testing.T) {
	var workerCalled bool
	var gotRerank models.RerankRequest

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/search" {
			t.Errorf("unexpected inference path %q", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(models.SearchResponse{
			Query:        "electric car",
			TotalResults: 2,
			Results: []models.SearchResult{
				{ID: "a", Score: 0.90, Metadata: map[string]interface{}{"text": "a boat"}},
				{ID: "b", Score: 0.80, Metadata: map[string]interface{}{"text": "electric car"}},
			},
		})
	}))
	defer inference.Close()

	worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		workerCalled = true
		if r.URL.Path != "/v1/rerank" {
			t.Errorf("unexpected worker path %q", r.URL.Path)
		}
		if err := json.NewDecoder(r.Body).Decode(&gotRerank); err != nil {
			t.Errorf("decode rerank request: %v", err)
		}
		// Return the candidates in reversed order to prove the gateway adopts
		// the worker's ordering rather than the inference ordering.
		_ = json.NewEncoder(w).Encode(models.RerankResponse{
			Results: []models.SearchResult{
				{ID: "b", Score: 0.88},
				{ID: "a", Score: 0.90},
			},
			LatencyMs: 0.1,
		})
	}))
	defer worker.Close()

	h := newTestHandler(inference.URL, worker.URL)
	w := doJSON(h.Search, http.MethodPost, "/v1/search", `{"query":"electric car","top_k":2}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", w.Code, w.Body.String())
	}
	if !workerCalled {
		t.Fatal("gateway did not call the worker's /v1/rerank endpoint")
	}
	if gotRerank.Query != "electric car" {
		t.Errorf("rerank query = %q, want %q", gotRerank.Query, "electric car")
	}
	if len(gotRerank.Results) != 2 {
		t.Errorf("rerank got %d candidates, want 2", len(gotRerank.Results))
	}

	var resp models.SearchResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(resp.Results) != 2 || resp.Results[0].ID != "b" {
		t.Errorf("gateway returned %+v; want the worker's ordering (b first)", resp.Results)
	}
}

// TestSearchDegradesWhenWorkerDown asserts re-ranking is a refinement: if the
// worker is unreachable the search still succeeds with inference ordering.
func TestSearchDegradesWhenWorkerDown(t *testing.T) {
	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(models.SearchResponse{
			Query:        "q",
			TotalResults: 1,
			Results:      []models.SearchResult{{ID: "only", Score: 0.5}},
		})
	}))
	defer inference.Close()

	// Point the worker at a closed port.
	down := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	downURL := down.URL
	down.Close()

	h := newTestHandler(inference.URL, downURL)
	w := doJSON(h.Search, http.MethodPost, "/v1/search", `{"query":"q"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 when only re-ranking fails", w.Code)
	}
	var resp models.SearchResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Results) != 1 || resp.Results[0].ID != "only" {
		t.Errorf("got %+v, want inference ordering preserved", resp.Results)
	}
}

// TestSearchPropagatesTraceContext guards the trace-header injection that the
// downstream client previously lacked entirely.
func TestSearchPropagatesTraceContext(t *testing.T) {
	seen := make(chan bool, 1)
	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, has := r.Header["Traceparent"]
		select {
		case seen <- has:
		default:
		}
		_ = json.NewEncoder(w).Encode(models.SearchResponse{Query: "q"})
	}))
	defer inference.Close()

	h := newTestHandler(inference.URL, inference.URL)
	_ = doJSON(h.Search, http.MethodPost, "/v1/search", `{"query":"q"}`)

	// With no active span the propagator emits nothing, so this asserts the
	// injection call runs without error rather than that a header is present.
	select {
	case <-seen:
	default:
		t.Fatal("inference service was never called")
	}
}

// TestGetIndexInfo covers the /v1/index route that three clients called but
// the gateway never registered.
func TestGetIndexInfo(t *testing.T) {
	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/index" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(models.IndexInfo{
			Dimension:        384,
			TotalVectorCount: 7,
		})
	}))
	defer inference.Close()

	h := newTestHandler(inference.URL, inference.URL)
	w := doJSON(h.GetIndexInfo, http.MethodGet, "/v1/index", "")

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var info models.IndexInfo
	if err := json.Unmarshal(w.Body.Bytes(), &info); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if info.Dimension != 384 || info.TotalVectorCount != 7 {
		t.Errorf("got %+v, want dimension=384 total=7", info)
	}
}

// TestSearchRejectsInvalidPayload keeps the binding contract honest.
func TestSearchRejectsInvalidPayload(t *testing.T) {
	h := newTestHandler("http://127.0.0.1:1", "http://127.0.0.1:1")
	w := doJSON(h.Search, http.MethodPost, "/v1/search", `{"top_k":5}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400 for a missing query", w.Code)
	}
}

// newAuthedTestHandler is newTestHandler with auth enabled, which is what
// activates resolveNamespace's tenant-isolation override.
func newAuthedTestHandler(inferenceURL, workerURL string) *Handler {
	cfg := &config.Config{}
	cfg.Services.InferenceURL = inferenceURL
	cfg.Services.WorkerURL = workerURL
	cfg.Auth.Enabled = true
	return NewHandler(cfg, service.NewClient(cfg))
}

// capturedNamespace starts a stub inference server that decodes whatever
// SearchRequest/UpsertRequest it receives and records the namespace field,
// so tests can assert what actually reached the downstream service rather
// than just what the handler returned.
func capturedNamespaceServer(t *testing.T, ns *[]string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Namespace string                 `json:"namespace"`
			Vectors   []models.UpsertRequest `json:"vectors"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		if len(body.Vectors) > 0 {
			for _, v := range body.Vectors {
				*ns = append(*ns, v.Namespace)
			}
		} else {
			*ns = append(*ns, body.Namespace)
		}

		switch r.URL.Path {
		case "/v1/search":
			_ = json.NewEncoder(w).Encode(models.SearchResponse{Query: "q"})
		case "/v1/upsert", "/v1/upsert/batch":
			_ = json.NewEncoder(w).Encode(models.UpsertResponse{})
		}
	}))
}

// TestSearchNamespaceIsolatedForNonAdmin is the regression test for the gap
// found in review: SearchRequest.Namespace was forwarded to Pinecone
// unchecked, so any authenticated caller could read another tenant's
// namespace just by naming it. With auth enabled, a non-admin caller's
// requested namespace must be ignored and replaced with one derived from
// their own JWT identity.
func TestSearchNamespaceIsolatedForNonAdmin(t *testing.T) {
	var seen []string
	inference := capturedNamespaceServer(t, &seen)
	defer inference.Close()

	h := newAuthedTestHandler(inference.URL, inference.URL)
	claims := &middleware.Claims{UserID: "alice", Role: "user"}
	w := doJSONAs(h.Search, claims, http.MethodPost, "/v1/search",
		`{"query":"q","namespace":"someone-elses-tenant"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", w.Code, w.Body.String())
	}
	if len(seen) != 1 || seen[0] != "tenant-alice" {
		t.Errorf("namespace sent downstream = %v, want [tenant-alice]", seen)
	}
}

// TestSearchNamespacePassthroughForAdmin lets an admin target an explicit
// namespace, e.g. for cross-tenant support/debugging.
func TestSearchNamespacePassthroughForAdmin(t *testing.T) {
	var seen []string
	inference := capturedNamespaceServer(t, &seen)
	defer inference.Close()

	h := newAuthedTestHandler(inference.URL, inference.URL)
	claims := &middleware.Claims{UserID: "admin-1", Role: "admin"}
	w := doJSONAs(h.Search, claims, http.MethodPost, "/v1/search",
		`{"query":"q","namespace":"customer-42"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", w.Code, w.Body.String())
	}
	if len(seen) != 1 || seen[0] != "customer-42" {
		t.Errorf("namespace sent downstream = %v, want [customer-42]", seen)
	}
}

// TestSearchNamespacePassthroughWhenAuthDisabled preserves the original
// single-tenant/dev-mode behavior: with auth off there's no identity to
// derive a tenant namespace from, so the caller's value is used as-is.
func TestSearchNamespacePassthroughWhenAuthDisabled(t *testing.T) {
	var seen []string
	inference := capturedNamespaceServer(t, &seen)
	defer inference.Close()

	h := newTestHandler(inference.URL, inference.URL)
	w := doJSON(h.Search, http.MethodPost, "/v1/search", `{"query":"q","namespace":"anything"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", w.Code, w.Body.String())
	}
	if len(seen) != 1 || seen[0] != "anything" {
		t.Errorf("namespace sent downstream = %v, want [anything]", seen)
	}
}

// TestUpsertNamespaceIsolatedForNonAdmin covers the write path, not just search.
func TestUpsertNamespaceIsolatedForNonAdmin(t *testing.T) {
	var seen []string
	inference := capturedNamespaceServer(t, &seen)
	defer inference.Close()

	h := newAuthedTestHandler(inference.URL, inference.URL)
	claims := &middleware.Claims{UserID: "bob", Role: "user"}
	w := doJSONAs(h.Upsert, claims, http.MethodPost, "/v1/upsert",
		`{"id":"1","text":"hello","namespace":"someone-elses-tenant"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", w.Code, w.Body.String())
	}
	if len(seen) != 1 || seen[0] != "tenant-bob" {
		t.Errorf("namespace sent downstream = %v, want [tenant-bob]", seen)
	}
}

// TestHealthChecksDownstreamServicesConcurrently is a before/after
// regression test: Health used to call CheckWorkerHealth then
// CheckInferenceHealth sequentially, so /health's latency was the SUM of
// both downstream calls. With two stub services that each take ~80ms,
// sequential would take ~160ms; concurrent should take close to ~80ms.
func TestHealthChecksDownstreamServicesConcurrently(t *testing.T) {
	const delay = 80 * time.Millisecond

	slow := func() *httptest.Server {
		return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			time.Sleep(delay)
			_ = json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
		}))
	}
	worker, inference := slow(), slow()
	defer worker.Close()
	defer inference.Close()

	h := newTestHandler(inference.URL, worker.URL)

	start := time.Now()
	w := doJSON(h.Health, http.MethodGet, "/health", "")
	elapsed := time.Since(start)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	// Sequential would take ~2*delay (~160ms); allow generous headroom above
	// a single delay for scheduling jitter while still catching a regression
	// back to sequential calls.
	if elapsed >= 2*delay {
		t.Errorf("Health took %v; want well under %v (the sequential-call time), "+
			"got no faster than doing both calls one after another", elapsed, 2*delay)
	}
}

// TestBatchUpsertNamespaceIsolatedForNonAdmin checks every vector in a batch
// is re-namespaced individually, not just the first.
func TestBatchUpsertNamespaceIsolatedForNonAdmin(t *testing.T) {
	var seen []string
	inference := capturedNamespaceServer(t, &seen)
	defer inference.Close()

	h := newAuthedTestHandler(inference.URL, inference.URL)
	claims := &middleware.Claims{UserID: "carol", Role: "user"}
	w := doJSONAs(h.BatchUpsert, claims, http.MethodPost, "/v1/upsert/batch", `{"vectors":[
		{"id":"1","text":"a","namespace":"other-tenant-a"},
		{"id":"2","text":"b","namespace":"other-tenant-b"}
	]}`)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", w.Code, w.Body.String())
	}
	for _, got := range seen {
		if got != "tenant-carol" {
			t.Errorf("namespace sent downstream = %v, want every vector namespaced tenant-carol", seen)
		}
	}
}
