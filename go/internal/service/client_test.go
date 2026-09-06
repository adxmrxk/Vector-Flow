package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/models"
)

func newClient(inferenceURL, workerURL string) *Client {
	cfg := &config.Config{}
	cfg.Services.InferenceURL = inferenceURL
	cfg.Services.WorkerURL = workerURL
	cfg.Services.Timeout = 5 * time.Second
	return NewClient(cfg)
}

func TestDownstreamErrorMessageExtractsEnvelope(t *testing.T) {
	e := &DownstreamError{
		Service: "inference",
		Status:  503,
		Body:    `{"error":"HTTPException","message":"Vector store not connected"}`,
	}
	if got := e.Message(); got != "Vector store not connected" {
		t.Errorf("Message() = %q", got)
	}
	if e.Error() == "" {
		t.Error("Error() should not be empty")
	}
}

func TestDownstreamErrorMessageFallsBackToBody(t *testing.T) {
	e := &DownstreamError{Service: "worker", Status: 500, Body: "plain text failure"}
	if got := e.Message(); got != "plain text failure" {
		t.Errorf("Message() = %q, want the raw body", got)
	}
}

func TestSearchReturnsTypedDownstreamError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"message":"Vector store not connected"}`))
	}))
	defer srv.Close()

	_, err := newClient(srv.URL, srv.URL).Search(context.Background(), &models.SearchRequest{Query: "q"})
	if err == nil {
		t.Fatal("expected an error")
	}
	de, ok := err.(*DownstreamError)
	if !ok {
		t.Fatalf("error type = %T, want *DownstreamError", err)
	}
	if de.Status != http.StatusServiceUnavailable {
		t.Errorf("Status = %d, want 503", de.Status)
	}
	if de.Message() != "Vector store not connected" {
		t.Errorf("Message() = %q", de.Message())
	}
}

func TestRerankPostsToWorker(t *testing.T) {
	var gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		_ = json.NewEncoder(w).Encode(models.RerankResponse{
			Results: []models.SearchResult{{ID: "a", Score: 1}},
		})
	}))
	defer srv.Close()

	resp, err := newClient("http://unused", srv.URL).Rerank(context.Background(),
		&models.RerankRequest{Query: "q", Results: []models.SearchResult{{ID: "a"}}})
	if err != nil {
		t.Fatalf("Rerank: %v", err)
	}
	if gotPath != "/v1/rerank" {
		t.Errorf("path = %q, want /v1/rerank", gotPath)
	}
	if len(resp.Results) != 1 {
		t.Errorf("results = %d, want 1", len(resp.Results))
	}
}

func TestCheckHealthClassifiesResponses(t *testing.T) {
	cases := []struct {
		code int
		want string
	}{
		{http.StatusOK, "healthy"},
		{http.StatusInternalServerError, "degraded"},
		{http.StatusServiceUnavailable, "degraded"},
	}
	for _, tc := range cases {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.code)
		}))
		got, _ := newClient(srv.URL, srv.URL).CheckInferenceHealth(context.Background())
		srv.Close()
		if got != tc.want {
			t.Errorf("status %d -> %q, want %q", tc.code, got, tc.want)
		}
	}
}

func TestCheckHealthReportsOfflineWhenUnreachable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	url := srv.URL
	srv.Close() // nothing is listening now

	got, err := newClient(url, url).CheckWorkerHealth(context.Background())
	if got != "offline" {
		t.Errorf("status = %q, want offline", got)
	}
	if err == nil {
		t.Error("expected an error for an unreachable service")
	}
}

func TestServiceLabelFor(t *testing.T) {
	c := newClient("http://inference:8082", "http://worker:8081")
	if got := c.serviceLabelFor("http://worker:8081"); got != "worker" {
		t.Errorf("worker URL labelled %q", got)
	}
	if got := c.serviceLabelFor("http://inference:8082"); got != "inference" {
		t.Errorf("inference URL labelled %q", got)
	}
}

func TestInjectTraceDoesNotPanicWithoutSpan(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	injectTrace(context.Background(), req) // no active span; must be a no-op
}
