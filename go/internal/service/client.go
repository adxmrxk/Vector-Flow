// Package service provides clients for communicating with downstream services.
package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/metrics"
	"github.com/vectorflow/gateway/internal/models"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// injectTrace writes W3C trace context headers onto an outgoing request so
// downstream services join the caller's trace instead of starting a new one.
func injectTrace(ctx context.Context, req *http.Request) {
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
}

// DownstreamError describes a non-2xx response from a downstream service.
type DownstreamError struct {
	Service string
	Status  int
	Body    string
}

func (e *DownstreamError) Error() string {
	return fmt.Sprintf("%s service returned %d: %s", e.Service, e.Status, e.Body)
}

// Message extracts the downstream's human-readable message when it returned a
// VectorFlow-style error envelope, falling back to the raw body.
func (e *DownstreamError) Message() string {
	var envelope struct {
		Message string `json:"message"`
		Detail  string `json:"detail"`
	}
	if err := json.Unmarshal([]byte(e.Body), &envelope); err == nil && envelope.Message != "" {
		return envelope.Message
	}
	return e.Body
}

// Client provides methods to communicate with downstream services.
type Client struct {
	httpClient   *http.Client
	inferenceURL string
	workerURL    string
}

// NewClient creates a new service client.
func NewClient(cfg *config.Config) *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: cfg.Services.Timeout,
		},
		inferenceURL: cfg.Services.InferenceURL,
		workerURL:    cfg.Services.WorkerURL,
	}
}

// ----- Inference Service Methods -----

// CreateEmbeddings calls the inference service to generate embeddings.
func (c *Client) CreateEmbeddings(ctx context.Context, req *models.EmbeddingRequest) (*models.EmbeddingResponse, error) {
	url := fmt.Sprintf("%s/v1/embeddings", c.inferenceURL)
	start := time.Now()

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "embeddings", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.EmbeddingResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// Search calls the inference service to perform semantic search.
func (c *Client) Search(ctx context.Context, req *models.SearchRequest) (*models.SearchResponse, error) {
	url := fmt.Sprintf("%s/v1/search", c.inferenceURL)
	start := time.Now()

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "search", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.SearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// Upsert calls the inference service to upsert a vector.
func (c *Client) Upsert(ctx context.Context, req *models.UpsertRequest) (*models.UpsertResponse, error) {
	url := fmt.Sprintf("%s/v1/upsert", c.inferenceURL)
	start := time.Now()

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "upsert", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.UpsertResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// BatchUpsert calls the inference service to batch upsert vectors.
func (c *Client) BatchUpsert(ctx context.Context, req *models.BatchUpsertRequest) (*models.UpsertResponse, error) {
	url := fmt.Sprintf("%s/v1/upsert/batch", c.inferenceURL)
	start := time.Now()

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "batch_upsert", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.UpsertResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// GetModelInfo retrieves model information from the inference service.
func (c *Client) GetModelInfo(ctx context.Context) (*models.ModelInfo, error) {
	url := fmt.Sprintf("%s/v1/model", c.inferenceURL)
	start := time.Now()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "model_info", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.ModelInfo
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// GetIndexInfo retrieves vector index statistics from the inference service.
func (c *Client) GetIndexInfo(ctx context.Context) (*models.IndexInfo, error) {
	url := fmt.Sprintf("%s/v1/index", c.inferenceURL)
	start := time.Now()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("inference", "index_info", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "inference", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.IndexInfo
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// ----- Worker Service Methods -----

// Rerank asks the Rust worker to re-score and reorder candidate results.
func (c *Client) Rerank(ctx context.Context, req *models.RerankRequest) (*models.RerankResponse, error) {
	url := fmt.Sprintf("%s/v1/rerank", c.workerURL)
	start := time.Now()

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	injectTrace(ctx, httpReq)

	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream("worker", "rerank", start, err)
	if err != nil {
		return nil, fmt.Errorf("failed to call worker service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, &DownstreamError{Service: "worker", Status: resp.StatusCode, Body: string(respBody)}
	}

	var result models.RerankResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &result, nil
}

// ----- Health Check Methods -----

// CheckInferenceHealth checks if the inference service is healthy.
func (c *Client) CheckInferenceHealth(ctx context.Context) (string, error) {
	return c.checkHealth(ctx, c.inferenceURL)
}

// CheckWorkerHealth checks if the worker service is healthy.
func (c *Client) CheckWorkerHealth(ctx context.Context) (string, error) {
	return c.checkHealth(ctx, c.workerURL)
}

// serviceLabel maps a base URL to a stable metric label.
func (c *Client) serviceLabelFor(baseURL string) string {
	if baseURL == c.workerURL {
		return "worker"
	}
	return "inference"
}

func (c *Client) checkHealth(ctx context.Context, baseURL string) (string, error) {
	url := fmt.Sprintf("%s/health", baseURL)

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "offline", fmt.Errorf("failed to create request: %w", err)
	}
	injectTrace(ctx, httpReq)

	start := time.Now()
	resp, err := c.httpClient.Do(httpReq)
	metrics.ObserveDownstream(c.serviceLabelFor(baseURL), "health", start, err)
	if err != nil {
		return "offline", fmt.Errorf("service unreachable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "degraded", nil
	}

	return "healthy", nil
}
