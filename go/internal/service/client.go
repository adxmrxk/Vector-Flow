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
	"github.com/vectorflow/gateway/internal/models"
)

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

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("inference service returned %d: %s", resp.StatusCode, string(respBody))
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

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("inference service returned %d: %s", resp.StatusCode, string(respBody))
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

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("inference service returned %d: %s", resp.StatusCode, string(respBody))
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

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("inference service returned %d: %s", resp.StatusCode, string(respBody))
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

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to call inference service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("inference service returned %d", resp.StatusCode)
	}

	var result models.ModelInfo
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

func (c *Client) checkHealth(ctx context.Context, baseURL string) (string, error) {
	url := fmt.Sprintf("%s/health", baseURL)

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "offline", fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return "offline", fmt.Errorf("service unreachable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "degraded", nil
	}

	return "healthy", nil
}
