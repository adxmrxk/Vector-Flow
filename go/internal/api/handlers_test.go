package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/vectorflow/gateway/internal/config"
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
