// Package api provides HTTP handlers for the gateway service.
package api

import (
	"errors"
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

// respondDownstream turns a downstream failure into a response that preserves
// the reason. A bare 500 for every failure mode made "Pinecone is not
// configured" indistinguishable from "the service crashed".
func respondDownstream(c *gin.Context, err error, fallbackMsg string) {
	var de *service.DownstreamError
	if errors.As(err, &de) {
		switch {
		case de.Status == http.StatusServiceUnavailable:
			c.JSON(http.StatusServiceUnavailable, models.NewErrorResponse(
				"ServiceUnavailable", de.Message()))
			return
		case de.Status >= 400 && de.Status < 500:
			c.JSON(de.Status, models.NewErrorResponse("BadRequest", de.Message()))
			return
		}
	}
	c.JSON(http.StatusInternalServerError, models.NewErrorResponse("InternalError", fallbackMsg))
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
		respondDownstream(c, err, "Failed to generate embeddings")
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
		respondDownstream(c, err, "Search failed")
		return
	}

	// Re-rank candidates on the Rust worker. Re-ranking is a refinement, not a
	// correctness requirement, so a worker failure degrades to the raw
	// inference ordering rather than failing the whole request.
	if len(result.Results) > 0 {
		reranked, rerankErr := h.client.Rerank(ctx, &models.RerankRequest{
			Query:   req.Query,
			Results: result.Results,
			TopK:    req.TopK,
		})
		if rerankErr != nil {
			log.Warn().Err(rerankErr).Str("query", req.Query).
				Msg("Re-rank failed, returning inference ordering")
		} else {
			result.Results = reranked.Results
			result.TotalResults = len(reranked.Results)
		}
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
		respondDownstream(c, err, "Upsert failed")
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
		respondDownstream(c, err, "Batch upsert failed")
		return
	}

	c.JSON(http.StatusOK, result)
}

// ----- Info Endpoints -----

// GetIndexInfo returns vector index statistics from the inference service.
func (h *Handler) GetIndexInfo(c *gin.Context) {
	ctx := c.Request.Context()
	result, err := h.client.GetIndexInfo(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get index info")
		respondDownstream(c, err, "Failed to get index info")
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetModelInfo returns information about the loaded model.
func (h *Handler) GetModelInfo(c *gin.Context) {
	ctx := c.Request.Context()
	result, err := h.client.GetModelInfo(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get model info")
		respondDownstream(c, err, "Failed to get model info")
		return
	}

	c.JSON(http.StatusOK, result)
}
