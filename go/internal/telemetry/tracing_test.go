package telemetry

import (
	"context"
	"testing"
)

func TestGetConfigFromEnvDefaults(t *testing.T) {
	t.Setenv("OTEL_TRACES_ENABLED", "")
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	t.Setenv("ENVIRONMENT", "")

	cfg := GetConfigFromEnv("svc", "1.2.3")

	if cfg.ServiceName != "svc" || cfg.ServiceVersion != "1.2.3" {
		t.Errorf("name/version = %q/%q", cfg.ServiceName, cfg.ServiceVersion)
	}
	if cfg.OTLPEndpoint != "localhost:4318" {
		t.Errorf("OTLPEndpoint = %q, want localhost:4318", cfg.OTLPEndpoint)
	}
	if cfg.Environment != "development" {
		t.Errorf("Environment = %q, want development", cfg.Environment)
	}
	if !cfg.Enabled {
		t.Error("Enabled = false; tracing should default on")
	}
}

// TestGetConfigFromEnvStripsScheme guards the http:// trimming: otlptracehttp
// takes a host:port endpoint and adds the scheme itself.
func TestGetConfigFromEnvStripsScheme(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://jaeger:4318")

	if got := GetConfigFromEnv("s", "v").OTLPEndpoint; got != "jaeger:4318" {
		t.Errorf("OTLPEndpoint = %q, want jaeger:4318", got)
	}
}

func TestGetConfigFromEnvDisabled(t *testing.T) {
	t.Setenv("OTEL_TRACES_ENABLED", "false")
	if GetConfigFromEnv("s", "v").Enabled {
		t.Error("Enabled = true, want false when OTEL_TRACES_ENABLED=false")
	}
}

// TestInitTracerDisabled is the regression test for the resource schema-URL
// conflict: InitTracer used to return an error and leave tracing off entirely.
func TestInitTracerDisabled(t *testing.T) {
	shutdown, err := InitTracer(Config{ServiceName: "s", ServiceVersion: "v", Enabled: false})
	if err != nil {
		t.Fatalf("InitTracer(disabled) error: %v", err)
	}
	if shutdown == nil {
		t.Fatal("shutdown func is nil")
	}
	if err := shutdown(context.Background()); err != nil {
		t.Errorf("shutdown: %v", err)
	}
}

func TestInitTracerEnabledBuildsResource(t *testing.T) {
	// The exporter is lazy, so an unreachable endpoint is fine here; this
	// asserts resource.Merge succeeds rather than failing on schema URLs.
	shutdown, err := InitTracer(Config{
		ServiceName:    "vectorflow-gateway",
		ServiceVersion: "0.1.0",
		Environment:    "test",
		OTLPEndpoint:   "127.0.0.1:4318",
		Enabled:        true,
	})
	if err != nil {
		t.Fatalf("InitTracer returned %v; the resource merge must not conflict", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	_ = shutdown(ctx)
}

func TestTracerIsNeverNil(t *testing.T) {
	if Tracer() == nil {
		t.Fatal("Tracer() returned nil")
	}
}

func TestStartSpanAndHelpers(t *testing.T) {
	ctx, span := StartSpan(context.Background(), "unit-test")
	if span == nil {
		t.Fatal("StartSpan returned a nil span")
	}
	// These are no-ops without a configured provider, but must not panic.
	AddEvent(ctx, "an-event")
	SetAttributes(ctx)
	RecordError(ctx, context.Canceled)
	span.End()
}
