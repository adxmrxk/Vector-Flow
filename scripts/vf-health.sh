#!/bin/bash
# Health check for VectorFlow services
# Usage: ./scripts/vf-health.sh [gateway-url]

set -e

GATEWAY_URL="${1:-${VECTORFLOW_GATEWAY_URL:-http://localhost:8080}}"

echo ""
echo "VectorFlow Health Check"
echo "Gateway: $GATEWAY_URL"
echo ""

check_endpoint() {
    local name="$1"
    local url="$2"
    printf "%-25s" "$name..."

    if response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null); then
        if [ "$response" == "200" ]; then
            echo "OK"
            return 0
        else
            echo "WARN (status: $response)"
            return 1
        fi
    else
        echo "FAIL (unreachable)"
        return 1
    fi
}

FAILED=0

check_endpoint "Gateway Health" "$GATEWAY_URL/health" || ((FAILED++))
check_endpoint "Gateway Ready" "$GATEWAY_URL/ready" || ((FAILED++))
check_endpoint "Model Info" "$GATEWAY_URL/v1/model" || ((FAILED++))
check_endpoint "Index Stats" "$GATEWAY_URL/v1/index" || ((FAILED++))

WORKER_URL="${RUST_WORKER_URL:-http://localhost:8081}"
INFERENCE_URL="${PYTHON_INFERENCE_URL:-http://localhost:8082}"

echo ""
check_endpoint "Rust Worker" "$WORKER_URL/health" || true
check_endpoint "Python Inference" "$INFERENCE_URL/health" || true

echo ""
if [ $FAILED -eq 0 ]; then
    echo "All critical services healthy"
    exit 0
else
    echo "$FAILED critical check(s) failed"
    exit 1
fi
