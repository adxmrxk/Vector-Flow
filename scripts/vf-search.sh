#!/bin/bash
# Quick search using curl
# Usage: ./scripts/vf-search.sh "query text" [top_k]

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 \"search query\" [top_k]"
    exit 1
fi

QUERY="$1"
TOP_K="${2:-10}"
GATEWAY_URL="${VECTORFLOW_GATEWAY_URL:-http://localhost:8080}"

echo "Searching: \"$QUERY\" (top $TOP_K)"
echo ""

RESPONSE=$(curl -s -X POST "$GATEWAY_URL/v1/search" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$QUERY\", \"topK\": $TOP_K, \"includeMetadata\": true}")

if echo "$RESPONSE" | grep -q '"error"'; then
    echo "Error: $(echo "$RESPONSE" | jq -r '.error // .message // "Unknown error"')"
    exit 1
fi

LATENCY=$(echo "$RESPONSE" | jq -r '.latencyMs // 0')
COUNT=$(echo "$RESPONSE" | jq -r '.results | length')

echo "Found $COUNT results in ${LATENCY}ms"
echo ""

echo "$RESPONSE" | jq -r '.results[] | "• \(.id) (\(.score * 100 | floor)%)"'
