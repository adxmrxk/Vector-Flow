package cache

import (
	"context"
	"os"
	"testing"

	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/models"
)

// testCache connects to a real Redis instance for integration-style
// verification of the caching logic. It's skipped when no Redis is
// reachable (e.g. a plain `go test ./...` on a machine without one running)
// rather than failing the build, mirroring how the rest of the suite
// degrades around unavailable infrastructure.
func testCache(t *testing.T) *Cache {
	t.Helper()

	redisURL := os.Getenv("TEST_REDIS_URL")
	if redisURL == "" {
		redisURL = "redis://localhost:16379/0"
	}

	cfg := &config.Config{}
	cfg.Cache.Enabled = true
	cfg.Cache.RedisURL = redisURL
	cfg.Cache.TTLSeconds = 60

	c := New(cfg)
	if c == nil {
		t.Skip("no Redis reachable at TEST_REDIS_URL / redis://localhost:16379/0; skipping cache integration tests")
	}

	// Isolate each test's keys so runs don't interfere with each other.
	t.Cleanup(func() {
		c.client.FlushDB(context.Background())
	})
	return c
}

// getSearch and setSearch mirror the Client.Search usage pattern: compute
// the key once via SearchKey, then Lookup/Store with it.
func getSearch(ctx context.Context, c *Cache, namespace string, req *models.SearchRequest) (*models.SearchResponse, bool) {
	return c.Lookup(ctx, c.SearchKey(ctx, namespace, req))
}

func setSearch(ctx context.Context, c *Cache, namespace string, req *models.SearchRequest, resp *models.SearchResponse) {
	c.Store(ctx, c.SearchKey(ctx, namespace, req), resp)
}

func TestDisabledCacheIsAlwaysANilSafeMiss(t *testing.T) {
	var c *Cache // New() returns nil when disabled; every method must tolerate that.

	if key := c.SearchKey(context.Background(), "ns", &models.SearchRequest{Query: "q"}); key != "" {
		t.Fatalf("nil cache produced a non-empty key: %q", key)
	}
	if _, hit := c.Lookup(context.Background(), "vectorflow:search:ns:v0:doesnotexist"); hit {
		t.Fatal("nil cache reported a hit")
	}
	// Must not panic.
	c.Store(context.Background(), "some-key", &models.SearchResponse{})
	c.InvalidateNamespace(context.Background(), "ns")
}

func TestSearchCacheMissThenHit(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()
	req := &models.SearchRequest{Query: "electric car", TopK: 5}

	if _, hit := getSearch(ctx, c, "tenant-a", req); hit {
		t.Fatal("expected a miss before anything was cached")
	}

	resp := &models.SearchResponse{Query: "electric car", TotalResults: 1}
	setSearch(ctx, c, "tenant-a", req, resp)

	got, hit := getSearch(ctx, c, "tenant-a", req)
	if !hit {
		t.Fatal("expected a hit after Store")
	}
	if got.Query != "electric car" || got.TotalResults != 1 {
		t.Errorf("got %+v, want the cached response", got)
	}
}

func TestSearchCacheIsScopedPerNamespace(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()
	req := &models.SearchRequest{Query: "same query"}

	setSearch(ctx, c, "tenant-a", req, &models.SearchResponse{Query: "a"})

	if _, hit := getSearch(ctx, c, "tenant-b", req); hit {
		t.Fatal("a cache entry for tenant-a leaked into tenant-b's namespace")
	}
}

func TestSearchCacheDistinguishesRequestShape(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()

	setSearch(ctx, c, "ns", &models.SearchRequest{Query: "q", TopK: 5}, &models.SearchResponse{TotalResults: 5})

	if _, hit := getSearch(ctx, c, "ns", &models.SearchRequest{Query: "q", TopK: 10}); hit {
		t.Fatal("a different top_k must not hit the same cache entry")
	}
	if _, hit := getSearch(ctx, c, "ns", &models.SearchRequest{Query: "different query", TopK: 5}); hit {
		t.Fatal("a different query must not hit the same cache entry")
	}
}

// TestInvalidateNamespaceOrphansPriorEntries is the regression test for the
// whole point of this cache: an upsert must not leave stale search results
// being served.
func TestInvalidateNamespaceOrphansPriorEntries(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()
	req := &models.SearchRequest{Query: "q"}

	setSearch(ctx, c, "tenant-a", req, &models.SearchResponse{TotalResults: 1})
	if _, hit := getSearch(ctx, c, "tenant-a", req); !hit {
		t.Fatal("setup: expected a hit before invalidation")
	}

	c.InvalidateNamespace(ctx, "tenant-a")

	if _, hit := getSearch(ctx, c, "tenant-a", req); hit {
		t.Fatal("expected a miss after invalidating the namespace")
	}
}

func TestInvalidateNamespaceDoesNotAffectOtherNamespaces(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()
	req := &models.SearchRequest{Query: "q"}

	setSearch(ctx, c, "tenant-a", req, &models.SearchResponse{TotalResults: 1})
	setSearch(ctx, c, "tenant-b", req, &models.SearchResponse{TotalResults: 2})

	c.InvalidateNamespace(ctx, "tenant-a")

	if _, hit := getSearch(ctx, c, "tenant-b", req); !hit {
		t.Error("invalidating tenant-a must not evict tenant-b's cache entries")
	}
}

// TestSearchKeyReusedAvoidsRedundantVersionLookups is the regression test for
// the round-trip reduction: computing the key once and reusing it for both
// the lookup and the store must produce a key that still resolves after a
// Store using that same precomputed key.
func TestSearchKeyReusedAvoidsRedundantVersionLookups(t *testing.T) {
	c := testCache(t)
	ctx := context.Background()
	req := &models.SearchRequest{Query: "q"}

	key := c.SearchKey(ctx, "tenant-a", req)
	if _, hit := c.Lookup(ctx, key); hit {
		t.Fatal("expected a miss before storing")
	}

	c.Store(ctx, key, &models.SearchResponse{TotalResults: 1})

	got, hit := c.Lookup(ctx, key)
	if !hit || got.TotalResults != 1 {
		t.Errorf("Lookup(%q) = %+v, %v; want the stored response", key, got, hit)
	}
}
