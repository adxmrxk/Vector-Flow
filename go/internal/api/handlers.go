// Package api provides HTTP handlers for the gateway service.
package api

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/models"
	"github.com/vectorflow/gateway/internal/service"
)

const version = "0.1.0"

// Handler holds dependencies for HTTP handlers.
type Handler struct {
	cfg    *config.Config
	client *service.Client
}

// NewHandler creates a new Handler instance.
func NewHandler(cfg *config.Config, client *service.Client) *Handler {
	return &Handler{
		cfg:    cfg,
		client: client,
	}
}

// ----- Health Endpoints -----

// Health handles health check requests.
func (h *Handler) Health(c *gin.Context) {
	ctx := c.Request.Context()

	workerStatus, _ := h.client.CheckWorkerHealth(ctx)
	inferenceStatus, _ := h.client.CheckInferenceHealth(ctx)

	status := "healthy"
	if workerStatus != "healthy" || inferenceStatus != "healthy" {
		status = "degraded"
	}

	c.JSON(http.StatusOK, models.HealthResponse{
		Status:          status,
		Version:         version,
		Environment:     h.cfg.Server.Environment,
		WorkerStatus:    workerStatus,
		InferenceStatus: inferenceStatus,
		Timestamp:       time.Now().UTC(),
	})
}

// Ready handles readiness check requests.
func (h *Handler) Ready(c *gin.Context) {
	ctx := c.Request.Context()

	_, err := h.client.CheckInferenceHealth(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, models.NewErrorResponse(
			"ServiceUnavailable",
			"Inference service not ready",
		))
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

// ----- Embedding Endpoints -----

// CreateEmbeddings handles embedding generation requests.
func (h *Handler) CreateEmbeddings(c *gin.Context) {
	var req models.EmbeddingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.NewErrorResponse(
			"ValidationError",
			err.Error(),
		))
		return
	}

	// Set default for normalize
	if !req.Normalize {
		req.Normalize = true
	}

	ctx := c.Request.Context()
	result, err := h.client.CreateEmbeddings(ctx, &req)
	if err != nil {
		log.Error().Err(err).Msg("Failed to create embeddings")
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"InternalError",
			"Failed to generate embeddings",
		))
		return
	}

	c.JSON(http.StatusOK, result)
}

// ----- Search Endpoints -----

// Search handles semantic search requests.
func (h *Handler) Search(c *gin.Context) {
	var req models.SearchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.NewErrorResponse(
			"ValidationError",
			err.Error(),
		))
		return
	}

	// Set defaults
	if req.TopK == 0 {
		req.TopK = 10
	}
	if !req.IncludeMetadata {
		req.IncludeMetadata = true
	}

	ctx := c.Request.Context()
	startTime := time.Now()

	result, err := h.client.Search(ctx, &req)
	if err != nil {
		log.Error().Err(err).Str("query", req.Query).Msg("Search failed")
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"InternalError",
			"Search failed",
		))
		return
	}

	// Add gateway latency
	result.LatencyMs = float64(time.Since(startTime).Milliseconds())

	c.JSON(http.StatusOK, result)
}

// ----- Upsert Endpoints -----

// Upsert handles single vector upsert requests.
func (h *Handler) Upsert(c *gin.Context) {
	var req models.UpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.NewErrorResponse(
			"ValidationError",
			err.Error(),
		))
		return
	}

	ctx := c.Request.Context()
	result, err := h.client.Upsert(ctx, &req)
	if err != nil {
		log.Error().Err(err).Str("id", req.ID).Msg("Upsert failed")
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"InternalError",
			"Upsert failed",
		))
		return
	}

	c.JSON(http.StatusOK, result)
}

// BatchUpsert handles batch vector upsert requests.
func (h *Handler) BatchUpsert(c *gin.Context) {
	var req models.BatchUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.NewErrorResponse(
			"ValidationError",
			err.Error(),
		))
		return
	}

	ctx := c.Request.Context()
	result, err := h.client.BatchUpsert(ctx, &req)
	if err != nil {
		log.Error().Err(err).Int("count", len(req.Vectors)).Msg("Batch upsert failed")
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"InternalError",
			"Batch upsert failed",
		))
		return
	}

	c.JSON(http.StatusOK, result)
}

// ----- Info Endpoints -----

// GetModelInfo returns information about the loaded model.
func (h *Handler) GetModelInfo(c *gin.Context) {
	ctx := c.Request.Context()
	result, err := h.client.GetModelInfo(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get model info")
		c.JSON(http.StatusInternalServerError, models.NewErrorResponse(
			"InternalError",
			"Failed to get model info",
		))
		return
	}

	c.JSON(http.StatusOK, result)
}
