// Package cache provides a Redis-backed cache for search results.
package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/cespare/xxhash/v2"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog/log"
	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/models"
)

// Cache is a Redis-backed cache for search results, scoped per namespace.
// Every repeated query previously re-embedded the query text and re-hit
// Pinecone even when nothing in that namespace had changed since the last
// identical search.
//
// It degrades to a no-op rather than failing a request: an unreachable or
// disabled Redis simply means every lookup is a cache miss, the same way
// re-ranking degrades when the worker is down.
type Cache struct {
	client *redis.Client
	ttl    time.Duration
}

// New connects to Redis if caching is enabled in config. It never blocks
// startup or returns an error: connectivity is checked with one bounded
// PING, and any failure (or Enabled=false) yields a disabled cache.
func New(cfg *config.Config) *Cache {
	if !cfg.Cache.Enabled {
		return nil
	}

	opts, err := redis.ParseURL(cfg.Cache.RedisURL)
	if err != nil {
		log.Warn().Err(err).Str("redis_url", cfg.Cache.RedisURL).
			Msg("Invalid Redis URL, search caching disabled")
		return nil
	}

	client := redis.NewClient(opts)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		log.Warn().Err(err).Msg("Redis unreachable, search caching disabled")
		return nil
	}

	log.Info().Str("redis_url", cfg.Cache.RedisURL).Msg("Search result cache connected")
	return &Cache{
		client: client,
		ttl:    time.Duration(cfg.Cache.TTLSeconds) * time.Second,
	}
}

// hashRequest fingerprints the parts of a search request that determine its
// result set, so two requests that only differ in, say, request ID still
// share a cache entry.
//
// This only needs to be a good, fast hash, not a cryptographic one -- the
// key never leaves the process and nothing here is adversarial input in the
// sense a cryptographic hash defends against. xxhash runs roughly an order
// of magnitude faster than SHA-256 for this; see cache_bench_test.go.
func hashRequest(req *models.SearchRequest) string {
	filterJSON, _ := json.Marshal(req.Filter)
	raw := fmt.Sprintf("%s|%d|%s|%t", req.Query, req.TopK, filterJSON, req.IncludeMetadata)
	return strconv.FormatUint(xxhash.Sum64String(raw), 16)
}

// version returns the namespace's current cache generation, defaulting to 0
// when it has never been invalidated (or Redis returns nothing for the key).
func (c *Cache) version(ctx context.Context, namespace string) int64 {
	v, err := c.client.Get(ctx, "vectorflow:nsver:"+namespace).Int64()
	if err != nil {
		return 0
	}
	return v
}

// SearchKey computes the cache key for a request, which is the only part of
// a lookup that needs the namespace's current version. Callers should
// compute this once per request and reuse it for both Lookup and Store: each
// separately calling GetSearch-then-SetSearch used to fetch the version
// twice, costing two extra Redis round trips on every cache miss.
func (c *Cache) SearchKey(ctx context.Context, namespace string, req *models.SearchRequest) string {
	if c == nil {
		return ""
	}
	return fmt.Sprintf("vectorflow:search:%s:v%d:%s", namespace, c.version(ctx, namespace), hashRequest(req))
}

// Lookup returns a cached response for the given (precomputed) key, or
// (nil, false) on any miss.
func (c *Cache) Lookup(ctx context.Context, key string) (*models.SearchResponse, bool) {
	if c == nil || key == "" {
		return nil, false
	}

	raw, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		return nil, false
	}

	var resp models.SearchResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, false
	}
	return &resp, true
}

// Store saves a search response under the given (precomputed) key for
// future identical searches in the namespace generation it was computed
// for. Failures are logged, not returned: caching is a performance
// optimization, never a correctness requirement.
func (c *Cache) Store(ctx context.Context, key string, resp *models.SearchResponse) {
	if c == nil || key == "" {
		return
	}

	raw, err := json.Marshal(resp)
	if err != nil {
		return
	}
	if err := c.client.Set(ctx, key, raw, c.ttl).Err(); err != nil {
		log.Debug().Err(err).Msg("Failed to write search cache entry")
	}
}

// InvalidateNamespace bumps the namespace's cache generation, which
// immediately orphans every existing entry for it. This avoids having to
// enumerate or delete individual keys (Redis has no "delete by prefix").
func (c *Cache) InvalidateNamespace(ctx context.Context, namespace string) {
	if c == nil {
		return
	}
	if err := c.client.Incr(ctx, "vectorflow:nsver:"+namespace).Err(); err != nil {
		log.Debug().Err(err).Str("namespace", namespace).Msg("Failed to invalidate namespace cache")
	}
}
