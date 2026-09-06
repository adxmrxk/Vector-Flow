package models

import (
	"encoding/json"
	"testing"
	"time"
)

func TestNewErrorResponse(t *testing.T) {
	before := time.Now().UTC()
	e := NewErrorResponse("ValidationError", "query is required")
	after := time.Now().UTC()

	if e.Error != "ValidationError" || e.Message != "query is required" {
		t.Errorf("got %+v", e)
	}
	if e.Timestamp.Before(before) || e.Timestamp.After(after) {
		t.Errorf("Timestamp %v outside [%v, %v]", e.Timestamp, before, after)
	}
}

// TestErrorResponseSerializes is the Go-side counterpart to the inference bug
// where a datetime field made the whole error response unserialisable.
func TestErrorResponseSerializes(t *testing.T) {
	b, err := json.Marshal(NewErrorResponse("InternalError", "boom"))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var round map[string]any
	if err := json.Unmarshal(b, &round); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	for _, k := range []string{"error", "message", "timestamp"} {
		if _, ok := round[k]; !ok {
			t.Errorf("missing key %q in %s", k, b)
		}
	}
	if _, ok := round["detail"]; ok {
		t.Error("empty detail should be omitted")
	}
}

// TestRerankRequestUsesWorkerFieldNames pins the wire contract against the
// Rust worker, which deserialises query/results/top_k.
func TestRerankRequestUsesWorkerFieldNames(t *testing.T) {
	b, err := json.Marshal(RerankRequest{
		Query:   "electric car",
		TopK:    3,
		Results: []SearchResult{{ID: "a", Score: 0.5}},
	})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var m map[string]any
	_ = json.Unmarshal(b, &m)

	for _, k := range []string{"query", "results", "top_k"} {
		if _, ok := m[k]; !ok {
			t.Errorf("missing %q in %s", k, b)
		}
	}
}

func TestRerankRequestOmitsZeroTopK(t *testing.T) {
	b, _ := json.Marshal(RerankRequest{Query: "q"})
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	if _, ok := m["top_k"]; ok {
		t.Errorf("top_k should be omitted when zero: %s", b)
	}
}

// TestSearchRequestFieldNames guards the snake_case contract the CLI got wrong.
func TestSearchRequestFieldNames(t *testing.T) {
	b, _ := json.Marshal(SearchRequest{Query: "q", TopK: 5, IncludeMetadata: true})
	var m map[string]any
	_ = json.Unmarshal(b, &m)

	for _, k := range []string{"query", "top_k", "include_metadata"} {
		if _, ok := m[k]; !ok {
			t.Errorf("missing %q in %s", k, b)
		}
	}
	for _, k := range []string{"topK", "includeMetadata"} {
		if _, ok := m[k]; ok {
			t.Errorf("unexpected camelCase key %q", k)
		}
	}
}

func TestIndexInfoFieldNames(t *testing.T) {
	b, _ := json.Marshal(IndexInfo{Dimension: 384, TotalVectorCount: 7})
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	if _, ok := m["total_vector_count"]; !ok {
		t.Errorf("missing total_vector_count in %s", b)
	}
}

func TestSearchResultOmitsEmptyMetadata(t *testing.T) {
	b, _ := json.Marshal(SearchResult{ID: "a", Score: 0.1})
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	if _, ok := m["metadata"]; ok {
		t.Errorf("empty metadata should be omitted: %s", b)
	}
}
