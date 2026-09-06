package config

import (
	"os"
	"testing"
)

// clearEnv unsets every variable Load reads so tests do not inherit the
// developer's shell or a .env-populated environment.
func clearEnv(t *testing.T) {
	t.Helper()
	for _, k := range []string{
		"GATEWAY_HOST", "GO_GATEWAY_PORT", "ENVIRONMENT",
		"WORKER_SERVICE_URL", "INFERENCE_SERVICE_URL",
		"AUTH_ENABLED", "JWT_SECRET", "JWT_EXPIRY",
		"API_KEYS", "API_KEY_HEADER", "LOG_LEVEL",
	} {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
}

func TestLoadDefaults(t *testing.T) {
	clearEnv(t)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if cfg.Server.Port != 8080 {
		t.Errorf("Server.Port = %d, want 8080", cfg.Server.Port)
	}
	if cfg.Services.WorkerURL != "http://localhost:8081" {
		t.Errorf("WorkerURL = %q", cfg.Services.WorkerURL)
	}
	if cfg.Services.InferenceURL != "http://localhost:8082" {
		t.Errorf("InferenceURL = %q", cfg.Services.InferenceURL)
	}
	if cfg.Auth.Enabled {
		t.Error("Auth.Enabled = true, want false by default")
	}
	if cfg.Auth.APIKeyHeader != "X-API-Key" {
		t.Errorf("APIKeyHeader = %q, want X-API-Key", cfg.Auth.APIKeyHeader)
	}
	if len(cfg.Auth.APIKeys) != 0 {
		t.Errorf("APIKeys = %v, want empty", cfg.Auth.APIKeys)
	}
}

func TestLoadReadsEnvironment(t *testing.T) {
	clearEnv(t)
	t.Setenv("WORKER_SERVICE_URL", "http://worker:9091")
	t.Setenv("INFERENCE_SERVICE_URL", "http://inference:9092")
	t.Setenv("AUTH_ENABLED", "true")
	t.Setenv("JWT_SECRET", "from-env")
	t.Setenv("ENVIRONMENT", "production")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if cfg.Services.WorkerURL != "http://worker:9091" {
		t.Errorf("WorkerURL = %q", cfg.Services.WorkerURL)
	}
	if cfg.Services.InferenceURL != "http://inference:9092" {
		t.Errorf("InferenceURL = %q", cfg.Services.InferenceURL)
	}
	if !cfg.Auth.Enabled {
		t.Error("Auth.Enabled = false, want true from AUTH_ENABLED")
	}
	if cfg.Auth.JWTSecret != "from-env" {
		t.Errorf("JWTSecret = %q", cfg.Auth.JWTSecret)
	}
}

// TestLoadParsesAPIKeys guards the comma-separated parsing that makes the
// API-key auth path reachable at all.
func TestLoadParsesAPIKeys(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_KEYS", "key-one, key-two ,,key-three")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	want := []string{"key-one", "key-two", "key-three"}
	if len(cfg.Auth.APIKeys) != len(want) {
		t.Fatalf("APIKeys = %v, want %v", cfg.Auth.APIKeys, want)
	}
	for i, k := range want {
		if cfg.Auth.APIKeys[i] != k {
			t.Errorf("APIKeys[%d] = %q, want %q", i, cfg.Auth.APIKeys[i], k)
		}
	}
}

func TestLoadIgnoresEmptyAPIKeys(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_KEYS", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if len(cfg.Auth.APIKeys) != 0 {
		t.Errorf("APIKeys = %v, want empty", cfg.Auth.APIKeys)
	}
}

func TestIsProduction(t *testing.T) {
	cases := map[string]bool{"production": true, "development": false, "staging": false}
	for env, want := range cases {
		cfg := &Config{}
		cfg.Server.Environment = env
		if got := cfg.IsProduction(); got != want {
			t.Errorf("IsProduction() with %q = %v, want %v", env, got, want)
		}
	}
}

func TestTimeoutsParseAsDurations(t *testing.T) {
	clearEnv(t)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if cfg.Server.ReadTimeout <= 0 {
		t.Errorf("ReadTimeout = %v, want a positive duration", cfg.Server.ReadTimeout)
	}
	if cfg.Services.Timeout <= 0 {
		t.Errorf("Services.Timeout = %v, want a positive duration", cfg.Services.Timeout)
	}
}
