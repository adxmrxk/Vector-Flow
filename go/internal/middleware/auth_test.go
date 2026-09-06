package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/vectorflow/gateway/internal/config"
)

func init() { gin.SetMode(gin.TestMode) }

// authCfg builds a config with auth enabled and the given API keys.
func authCfg(keys ...string) *config.Config {
	cfg := &config.Config{}
	cfg.Auth.Enabled = true
	cfg.Auth.JWTSecret = "test-secret"
	cfg.Auth.APIKeyHeader = "X-API-Key"
	cfg.Auth.APIKeys = keys
	return cfg
}

// run sends one request through JWTAuth and reports the status plus whether
// the protected handler was reached.
func run(cfg *config.Config, headers map[string]string) (int, bool) {
	reached := false
	w := httptest.NewRecorder()
	c, engine := gin.CreateTestContext(w)
	engine.Use(JWTAuth(cfg))
	engine.GET("/protected", func(c *gin.Context) {
		reached = true
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	c.Request = req
	engine.ServeHTTP(w, req)
	return w.Code, reached
}

// TestAPIKeyAuthAccepted covers the "optional API key headers" path, which was
// unreachable before API_KEYS could be configured.
func TestAPIKeyAuthAccepted(t *testing.T) {
	status, reached := run(authCfg("secret-key-one", "secret-key-two"),
		map[string]string{"X-API-Key": "secret-key-two"})

	if status != http.StatusOK || !reached {
		t.Fatalf("status=%d reached=%v; want 200 and handler reached", status, reached)
	}
}

func TestAPIKeyAuthRejectsUnknownKey(t *testing.T) {
	status, reached := run(authCfg("secret-key-one"),
		map[string]string{"X-API-Key": "not-a-real-key"})

	if status != http.StatusUnauthorized || reached {
		t.Fatalf("status=%d reached=%v; want 401 and handler not reached", status, reached)
	}
}

func TestAPIKeyAuthRejectsWhenNoKeysConfigured(t *testing.T) {
	status, reached := run(authCfg(), map[string]string{"X-API-Key": "anything"})

	if status != http.StatusUnauthorized || reached {
		t.Fatalf("status=%d reached=%v; want 401 when no keys are configured", status, reached)
	}
}

func TestMissingCredentialsRejected(t *testing.T) {
	status, _ := run(authCfg("k"), nil)
	if status != http.StatusUnauthorized {
		t.Errorf("status=%d, want 401 with no credentials", status)
	}
}

func TestAuthDisabledAllowsRequest(t *testing.T) {
	cfg := authCfg("k")
	cfg.Auth.Enabled = false

	status, reached := run(cfg, nil)
	if status != http.StatusOK || !reached {
		t.Errorf("status=%d reached=%v; want the request to pass when auth is disabled", status, reached)
	}
}

func TestMalformedAuthorizationHeaderRejected(t *testing.T) {
	for _, h := range []string{"Bearer", "Basic abc", "token abc"} {
		status, reached := run(authCfg("k"), map[string]string{"Authorization": h})
		if status != http.StatusUnauthorized || reached {
			t.Errorf("header %q: status=%d reached=%v; want 401", h, status, reached)
		}
	}
}
