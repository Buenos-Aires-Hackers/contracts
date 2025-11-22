#!/bin/bash

# Script to compress web proof using vlayer API
# Usage: ./compress_web_proof.sh <web_proof_json_file> <extraction_queries_json>

set -e

WEB_PROOF_FILE=$1
EXTRACTION_QUERIES=$2

if [ -z "$WEB_PROOF_FILE" ] || [ ! -f "$WEB_PROOF_FILE" ]; then
    echo "Error: Web proof file not found: $WEB_PROOF_FILE" >&2
    exit 1
fi

if [ -z "$EXTRACTION_QUERIES" ]; then
    echo "Error: Extraction queries JSON not provided" >&2
    exit 1
fi

# Read the web proof JSON
WEB_PROOF=$(cat "$WEB_PROOF_FILE")

# Construct the request payload
REQUEST_PAYLOAD=$(cat <<EOF
{
  "presentation": $WEB_PROOF,
  "extraction": $EXTRACTION_QUERIES
}
EOF
)

# Call vlayer API
RESPONSE=$(curl -s -X POST \
  "https://api.vlayer.xyz/api/v0/compress-web-proof" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_PAYLOAD")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
    echo "Error from vlayer API:" >&2
    echo "$RESPONSE" | jq '.error' >&2
    exit 1
fi

# Output the response
echo "$RESPONSE"
