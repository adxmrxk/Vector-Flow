// Package metrics provides Prometheus instrumentation for the gateway.
package metrics

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// RequestCount counts gateway HTTP requests by route and status.
	RequestCount = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "vectorflow_gateway_requests_total",
			Help: "Total HTTP requests handled by the gateway.",
		},
		[]string{"method", "endpoint", "status"},
	)

	// RequestLatency observes end-to-end gateway handling time.
	RequestLatency = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "vectorflow_gateway_request_latency_seconds",
			Help:    "Gateway request latency in seconds.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint"},
	)

	// DownstreamLatency observes calls the gateway makes to worker/inference.
	DownstreamLatency = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "vectorflow_gateway_downstream_latency_seconds",
			Help:    "Latency of gateway calls to downstream services.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"service", "operation"},
	)

	// DownstreamErrors counts failed downstream calls.
	DownstreamErrors = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "vectorflow_gateway_downstream_errors_total",
			Help: "Failed gateway calls to downstream services.",
		},
		[]string{"service", "operation"},
	)
)

// ObserveDownstream records the duration and outcome of a downstream call.
func ObserveDownstream(service, operation string, start time.Time, err error) {
	DownstreamLatency.WithLabelValues(service, operation).Observe(time.Since(start).Seconds())
	if err != nil {
		DownstreamErrors.WithLabelValues(service, operation).Inc()
	}
}

// Middleware returns a Gin middleware that records request metrics.
func Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		// Use the matched route, not the raw path, to keep cardinality bounded.
		endpoint := c.FullPath()
		if endpoint == "" {
			endpoint = "unmatched"
		}

		RequestCount.WithLabelValues(
			c.Request.Method,
			endpoint,
			strconv.Itoa(c.Writer.Status()),
		).Inc()

		RequestLatency.WithLabelValues(
			c.Request.Method,
			endpoint,
		).Observe(time.Since(start).Seconds())
	}
}
