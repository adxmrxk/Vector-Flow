package cache

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strconv"
	"testing"

	"github.com/cespare/xxhash/v2"
)

// sha256Hash is the pre-fix implementation, kept here only to benchmark
// against, so the improvement is measured against the exact prior code
// rather than a generic comparison.
func sha256Hash(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func xxhashHash(raw string) string {
	return strconv.FormatUint(xxhash.Sum64String(raw), 16)
}

// BenchmarkCacheKeyHash_Before is SHA-256, the cryptographic hash the cache
// key used before this change, despite the key never needing cryptographic
// properties (it's an internal Redis key, not exposed or adversarial).
func BenchmarkCacheKeyHash_Before(b *testing.B) {
	raw := fmt.Sprintf("%s|%d|%s|%t", "electric car charging stations near me", 10, `{"category":"automotive"}`, true)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		sha256Hash(raw)
	}
}

// BenchmarkCacheKeyHash_After is xxhash, what hashRequest uses now.
func BenchmarkCacheKeyHash_After(b *testing.B) {
	raw := fmt.Sprintf("%s|%d|%s|%t", "electric car charging stations near me", 10, `{"category":"automotive"}`, true)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		xxhashHash(raw)
	}
}
