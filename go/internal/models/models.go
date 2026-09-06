// Package models defines the data structures for API requests and responses.
package models

import "time"

// ----- Request Models -----

// EmbeddingRequest represents a request to generate embeddings.
type EmbeddingRequest struct {
	Texts     []string `json:"texts" binding:"required,min=1,max=100"`
	Normalize bool     `json:"normalize"`
}

// SearchRequest represents a semantic search request.
type SearchRequest struct {
	Query           string                 `json:"query" binding:"required,min=1,max=10000"`
	TopK            int                    `json:"top_k" binding:"omitempty,min=1,max=100"`
	Namespace       string                 `json:"namespace,omitempty"`
	Filter          map[string]interface{} `json:"filter,omitempty"`
	IncludeMetadata bool                   `json:"include_metadata"`
}

// UpsertRequest represents a request to upsert a vector.
type UpsertRequest struct {
	ID        string                 `json:"id" binding:"required"`
	Text      string                 `json:"text" binding:"required"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
	Namespace string                 `json:"namespace,omitempty"`
}

// BatchUpsertRequest represents a batch upsert request.
type BatchUpsertRequest struct {
	Vectors []UpsertRequest `json:"vectors" binding:"required,min=1,max=100"`
}

// ----- Response Models -----

// EmbeddingResponse represents the response from embedding generation.
type EmbeddingResponse struct {
	Embeddings [][]float64 `json:"embeddings"`
	Model      string      `json:"model"`
	Dimension  int         `json:"dimension"`
	Usage      Usage       `json:"usage"`
}

// Usage represents token usage statistics.
type Usage struct {
	TotalTexts      int `json:"total_texts"`
	EstimatedTokens int `json:"estimated_tokens"`
}

// SearchResult represents a single search result.
type SearchResult struct {
	ID       string                 `json:"id"`
	Score    float64                `json:"score"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
}

// SearchResponse represents the response from a search query.
type SearchResponse struct {
	Results      []SearchResult `json:"results"`
	Query        string         `json:"query"`
	TotalResults int            `json:"total_results"`
	LatencyMs    float64        `json:"latency_ms"`
}

// UpsertResponse represents the response from an upsert operation.
type UpsertResponse struct {
	UpsertedCount int      `json:"upserted_count"`
	IDs           []string `json:"ids"`
}

// HealthResponse represents the health check response.
type HealthResponse struct {
	Status            string    `json:"status"`
	Version           string    `json:"version"`
	Environment       string    `json:"environment"`
	WorkerStatus      string    `json:"worker_status"`
	InferenceStatus   string    `json:"inference_status"`
	Timestamp         time.Time `json:"timestamp"`
}

// ModelInfo represents information about the loaded model.
type ModelInfo struct {
	ModelName         string `json:"model_name"`
	Dimension         int    `json:"dimension"`
	MaxSequenceLength int    `json:"max_sequence_length"`
	Device            string `json:"device"`
	Loaded            bool   `json:"loaded"`
}

// RerankRequest is the payload sent to the Rust worker's /v1/rerank endpoint.
type RerankRequest struct {
	Query   string         `json:"query"`
	Results []SearchResult `json:"results"`
	TopK    int            `json:"top_k,omitempty"`
}

// RerankResponse is the Rust worker's re-ranked result set.
type RerankResponse struct {
	Results   []SearchResult `json:"results"`
	LatencyMs float64        `json:"latency_ms"`
}

// IndexInfo represents vector index statistics.
type IndexInfo struct {
	Dimension        int                    `json:"dimension"`
	TotalVectorCount int                    `json:"total_vector_count"`
	Namespaces       map[string]interface{} `json:"namespaces"`
}

// ErrorResponse represents an error response.
type ErrorResponse struct {
	Error     string    `json:"error"`
	Message   string    `json:"message"`
	Detail    string    `json:"detail,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

// NewErrorResponse creates a new error response.
func NewErrorResponse(err, message string) ErrorResponse {
	return ErrorResponse{
		Error:     err,
		Message:   message,
		Timestamp: time.Now().UTC(),
	}
}
