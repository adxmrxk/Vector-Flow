#!/bin/bash
# =========================
# VectorFlow Smoke Tests
# =========================
# Run after deployment to verify services are healthy

set -e

ENVIRONMENT=${1:-staging}
NAMESPACE="vectorflow-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo ""
echo "=============================================="
echo "   VectorFlow Smoke Tests - ${ENVIRONMENT}"
echo "=============================================="
echo ""

# Get service URLs
GATEWAY_URL=$(kubectl get svc vectorflow-gateway -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "localhost")
GATEWAY_PORT=$(kubectl get svc vectorflow-gateway -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].port}')

if [ -z "$GATEWAY_URL" ] || [ "$GATEWAY_URL" == "localhost" ]; then
    # Use port-forward for local testing
    log_info "Setting up port-forward for testing..."
    kubectl port-forward svc/vectorflow-gateway 8080:8080 -n ${NAMESPACE} &
    PF_PID=$!
    sleep 5
    GATEWAY_URL="localhost"
    GATEWAY_PORT="8080"
fi

BASE_URL="http://${GATEWAY_URL}:${GATEWAY_PORT}"

TESTS_PASSED=0
TESTS_FAILED=0

# ----- Test Functions -----

test_endpoint() {
    local name=$1
    local method=$2
    local endpoint=$3
    local expected_status=$4
    local data=$5

    log_info "Testing: $name"

    if [ "$method" == "GET" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}${endpoint}" || echo "000")
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$data" "${BASE_URL}${endpoint}" || echo "000")
    fi

    if [ "$response" == "$expected_status" ]; then
        log_pass "$name (HTTP $response)"
        ((TESTS_PASSED++))
    else
        log_fail "$name (Expected $expected_status, got $response)"
        ((TESTS_FAILED++))
    fi
}

# ----- Health Checks -----
log_info "Running health checks..."

test_endpoint "Gateway Health" "GET" "/health" "200"
test_endpoint "Gateway Readiness" "GET" "/ready" "200"

# ----- API Endpoints -----
log_info "Testing API endpoints..."

test_endpoint "Embeddings Endpoint" "POST" "/v1/embeddings" "200" '{"texts": ["test query"], "normalize": true}'
test_endpoint "Model Info" "GET" "/v1/model" "200"

# ----- Latency Test -----
log_info "Testing response latency..."

start_time=$(date +%s%N)
curl -s "${BASE_URL}/health" > /dev/null
end_time=$(date +%s%N)

latency=$(( (end_time - start_time) / 1000000 ))
if [ $latency -lt 1000 ]; then
    log_pass "Health endpoint latency: ${latency}ms"
    ((TESTS_PASSED++))
else
    log_fail "Health endpoint latency too high: ${latency}ms"
    ((TESTS_FAILED++))
fi

# ----- Cleanup -----
if [ -n "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

# ----- Summary -----
echo ""
echo "=============================================="
echo "   Test Results"
echo "=============================================="
echo ""
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    log_fail "Some tests failed!"
    exit 1
else
    log_pass "All tests passed!"
    exit 0
fi
