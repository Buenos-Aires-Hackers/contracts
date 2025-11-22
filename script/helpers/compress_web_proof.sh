#!/bin/bash

# Script to generate and compress web proof using vlayer API
# Usage: ./compress_web_proof.sh <url-or-web_proof_file> <extraction_queries_json>
# 
# If first argument is a URL (starts with http), it will:
#   1. Call /prove endpoint to generate web proof
#   2. Compress the proof using /compress-web-proof endpoint
#
# If first argument is a file, it will:
#   1. Read the presentation object from the file
#   2. Compress the proof using /compress-web-proof endpoint
#
# The web_proof_json_file should contain the presentation object from TLSN Web Prover:
#   {
#     "data": "...",
#     "version": "0.1.0-alpha.12",
#     "meta": {
#       "notaryUrl": "https://..."
#     }
#   }
#
# The extraction_queries_json should contain the extraction object:
#   {
#     "response.body": {
#       "jmespath": ["field1", "field2"]
#     }
#   }
#
# Environment variables:
#   VLAYER_API_URL - Override the compress API endpoint (default: https://zk-prover.vlayer.xyz/api/v0/compress-web-proof)
#   WEB_PROVER_URL - Override the prove API endpoint (default: https://web-prover.vlayer.xyz/api/v1/prove)
#   VLAYER_CLIENT_ID - Client ID for authentication
#   VLAYER_API_KEY - API Key for authentication
#
# Documentation: 
#   https://docs.vlayer.xyz/server-side/rest-api/prove
#   https://docs.vlayer.xyz/blockchain/rest-api/compress-web-proof

set -e

INPUT=$1
EXTRACTION_QUERIES=$2

if [ -z "$INPUT" ]; then
    echo "Error: URL or web proof file required" >&2
    exit 1
fi

if [ -z "$EXTRACTION_QUERIES" ] || [ ! -f "$EXTRACTION_QUERIES" ]; then
    echo "Error: Extraction queries file not found: $EXTRACTION_QUERIES" >&2
    exit 1
fi

# Get credentials from environment or use defaults
VLAYER_CLIENT_ID="${VLAYER_CLIENT_ID:-3006e6ae-1252-4444-9f62-f991f9da02e9}"
VLAYER_API_KEY="${VLAYER_API_KEY:-Eb1cLVBBZIcoidDWZSQ9AM53RgUJo7qLyeBcpjqbgDITb3xh4VBBJsBAXiLnnSDa}"

# Check if input is a URL or file
if [[ "$INPUT" =~ ^https?:// ]]; then
    # It's a URL - generate web proof first
    WEB_PROVER_URL="${WEB_PROVER_URL:-https://web-prover.vlayer.xyz/api/v1/prove}"
    
    echo "🌐 Generating web proof for: $INPUT" >&2
    echo "   Using prover: $WEB_PROVER_URL" >&2
    
    # Call /prove endpoint
    PROVE_RESPONSE=$(curl -s -X POST \
      "$WEB_PROVER_URL" \
      -H "Content-Type: application/json" \
      -H "x-client-id: $VLAYER_CLIENT_ID" \
      -H "Authorization: Bearer $VLAYER_API_KEY" \
      -d "{\"url\": \"$INPUT\", \"headers\": []}" 2>&1)
    
    # Check if request was successful
    if ! echo "$PROVE_RESPONSE" | jq -e '.success == true' > /dev/null 2>&1 && ! echo "$PROVE_RESPONSE" | jq -e '.data' > /dev/null 2>&1; then
        echo "Error: Failed to generate web proof" >&2
        echo "Response:" >&2
        echo "$PROVE_RESPONSE" | jq . >&2
        exit 1
    fi
    
    # Extract presentation (handle both {success: true, data: {...}} and direct format)
    # The presentation should have: data, version, meta fields
    if echo "$PROVE_RESPONSE" | jq -e '.data.data' > /dev/null 2>&1; then
        # Response is {success: true, data: {data, version, meta}}
        WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.data')
    elif echo "$PROVE_RESPONSE" | jq -e '.data' > /dev/null 2>&1 && echo "$PROVE_RESPONSE" | jq -e '.data | type == "object"' > /dev/null 2>&1; then
        # Response is {data: {data, version, meta}}
        WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.data')
    else
        # Response is direct presentation object
        WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.')
    fi
    
    echo "✅ Web proof generated successfully" >&2
else
    # It's a file - read the web proof
    if [ ! -f "$INPUT" ]; then
        echo "Error: Web proof file not found: $INPUT" >&2
        exit 1
    fi
    
    echo "📄 Reading web proof from file: $INPUT" >&2
    WEB_PROOF=$(cat "$INPUT")
    
    # Check if file is in correct presentation format (has data, version, meta fields)
    if ! echo "$WEB_PROOF" | jq -e '.data' > /dev/null 2>&1 || ! echo "$WEB_PROOF" | jq -e '.version' > /dev/null 2>&1 || ! echo "$WEB_PROOF" | jq -e '.meta' > /dev/null 2>&1; then
        # File is not in presentation format - check if it contains a URL we can use
        if echo "$WEB_PROOF" | jq -e '.url' > /dev/null 2>&1 || echo "$WEB_PROOF" | jq -e '.request.url' > /dev/null 2>&1; then
            # Extract URL from the file
            if echo "$WEB_PROOF" | jq -e '.url' > /dev/null 2>&1; then
                URL=$(echo "$WEB_PROOF" | jq -r '.url')
            else
                URL=$(echo "$WEB_PROOF" | jq -r '.request.url')
            fi
            
            echo "⚠️  File is not a presentation object. Detected URL: $URL" >&2
            echo "   Generating web proof from URL instead..." >&2
            
            # Generate proof from URL
            WEB_PROVER_URL="${WEB_PROVER_URL:-https://web-prover.vlayer.xyz/api/v1/prove}"
            PROVE_RESPONSE=$(curl -s -X POST \
              "$WEB_PROVER_URL" \
              -H "Content-Type: application/json" \
              -H "x-client-id: $VLAYER_CLIENT_ID" \
              -H "Authorization: Bearer $VLAYER_API_KEY" \
              -d "{\"url\": \"$URL\", \"headers\": []}" 2>&1)
            
            # Check for errors in the response
            if echo "$PROVE_RESPONSE" | jq -e '.success == false' > /dev/null 2>&1; then
                ERROR_CODE=$(echo "$PROVE_RESPONSE" | jq -r '.error.code // "UNKNOWN"')
                ERROR_MSG=$(echo "$PROVE_RESPONSE" | jq -r '.error.message // "Unknown error"')
                
                echo "Error: Failed to generate web proof from URL" >&2
                echo "  Code: $ERROR_CODE" >&2
                echo "  Message: $ERROR_MSG" >&2
                echo "  URL: $URL" >&2
                echo "" >&2
                echo "This usually means:" >&2
                echo "  - The URL requires authentication (e.g., Amazon order pages)" >&2
                echo "  - The URL is not accessible publicly" >&2
                echo "  - The web prover service is experiencing issues" >&2
                echo "" >&2
                echo "For testing, you can:" >&2
                echo "  1. Use a public API URL (e.g., https://data-api.binance.vision/api/v3/ticker/price?symbol=ETHUSDC)" >&2
                echo "  2. Set WEB_PROOF_URL environment variable to override the listing URL" >&2
                
                echo "{\"error\": \"$ERROR_CODE\", \"message\": $(echo "$ERROR_MSG" | jq -R .)}" >&1
                exit 1
            fi
            
            # Extract presentation
            if echo "$PROVE_RESPONSE" | jq -e '.data.data' > /dev/null 2>&1; then
                WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.data')
            elif echo "$PROVE_RESPONSE" | jq -e '.data' > /dev/null 2>&1 && echo "$PROVE_RESPONSE" | jq -e '.data | type == "object"' > /dev/null 2>&1; then
                WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.data')
            else
                WEB_PROOF=$(echo "$PROVE_RESPONSE" | jq -c '.')
            fi
            echo "✅ Web proof generated from URL" >&2
        else
            echo "Error: File does not contain a valid web proof presentation" >&2
            echo "   Expected format: {\"data\": \"...\", \"version\": \"...\", \"meta\": {...}}" >&2
            echo "   Or provide a URL/file with a 'url' field to generate proof from" >&2
            echo '{"error": "Invalid web proof file format"}' >&1
            exit 1
        fi
    else
        # File is in correct format, use as-is
        WEB_PROOF=$(echo "$WEB_PROOF" | jq -c '.')
    fi
fi

# Read the extraction queries JSON
EXTRACTION_QUERIES_CONTENT=$(cat "$EXTRACTION_QUERIES")

# Validate JSON format
if ! echo "$EXTRACTION_QUERIES_CONTENT" | jq . > /dev/null 2>&1; then
    echo "Error: Invalid JSON format in extraction queries file" >&2
    exit 1
fi

# Convert extraction queries format if needed
# Old format: {"response.body": [{"jmespath": "field1"}]}
# New format: {"response.body": {"jmespath": ["field1"]}}
if echo "$EXTRACTION_QUERIES_CONTENT" | jq -e '.["response.body"] | type == "array"' > /dev/null 2>&1; then
    # Convert old format to new format
    EXTRACTION_QUERIES_CONTENT=$(echo "$EXTRACTION_QUERIES_CONTENT" | jq -c '{
      "response.body": {
        "jmespath": (.["response.body"] | map(.["jmespath"]))
      }
    }')
    echo "⚠️  Converted extraction queries format (array to object)" >&2
fi

# Normalize JSON to ensure consistent formatting (critical for queries hash computation)
# This removes whitespace differences and ensures consistent key ordering
EXTRACTION_QUERIES_CONTENT=$(echo "$EXTRACTION_QUERIES_CONTENT" | jq -c .)

# Construct the request payload according to API documentation
# The presentation should be the direct output from Web Prover Server /prove endpoint
REQUEST_PAYLOAD=$(cat <<EOF
{
  "presentation": $WEB_PROOF,
  "extraction": $EXTRACTION_QUERIES_CONTENT
}
EOF
)

# Get API URL from environment or use default (from official docs)
VLAYER_API_URL="${VLAYER_API_URL:-https://zk-prover.vlayer.xyz/api/v0/compress-web-proof}"

# Get credentials from environment or use defaults
VLAYER_CLIENT_ID="${VLAYER_CLIENT_ID:-3006e6ae-1252-4444-9f62-f991f9da02e9}"
VLAYER_API_KEY="${VLAYER_API_KEY:-Eb1cLVBBZIcoidDWZSQ9AM53RgUJo7qLyeBcpjqbgDITb3xh4VBBJsBAXiLnnSDa}"

# Validate credentials are set
if [ -z "$VLAYER_CLIENT_ID" ] || [ -z "$VLAYER_API_KEY" ]; then
    echo "Error: VLAYER_CLIENT_ID and VLAYER_API_KEY must be set" >&2
    exit 1
fi

# Call vlayer API with authentication (per official documentation)
# Headers: x-client-id (lowercase with hyphens) and Authorization: Bearer
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$VLAYER_API_URL" \
  -H "Content-Type: application/json" \
  -H "x-client-id: $VLAYER_CLIENT_ID" \
  -H "Authorization: Bearer $VLAYER_API_KEY" \
  -d "$REQUEST_PAYLOAD" 2>&1) || {
    echo "Error: Failed to connect to vlayer API at $VLAYER_API_URL" >&2
    echo "Please check:" >&2
    echo "  1. Your internet connection" >&2
    echo "  2. The API endpoint is correct" >&2
    echo "  3. Your credentials are valid" >&2
    echo "  4. Set VLAYER_API_URL, VLAYER_CLIENT_ID, VLAYER_API_KEY if needed" >&2
    exit 1
}

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
# Extract response body (all but last line)
# Use sed to remove the last line (works on both Linux and macOS)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check HTTP status code
if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
    echo "Error: Failed to connect to vlayer API at $VLAYER_API_URL" >&2
    echo "This usually means:" >&2
    echo "  - The domain cannot be resolved (DNS issue)" >&2
    echo "  - The server is unreachable" >&2
    echo "  - Network connectivity problems" >&2
    echo "" >&2
    echo "You can override the API URL by setting VLAYER_API_URL environment variable" >&2
    exit 1
fi

# Check if response is valid JSON first
if ! echo "$RESPONSE_BODY" | jq . > /dev/null 2>&1; then
    echo "Error: Invalid JSON response from vlayer API" >&2
    echo "HTTP Status: $HTTP_CODE" >&2
    echo "Response:" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
fi

# Check for API-level errors (per API documentation format)
# API returns errors with success: false even for HTTP 200, so check this first
if echo "$RESPONSE_BODY" | jq -e '.success == false' > /dev/null 2>&1; then
    ERROR_CODE=$(echo "$RESPONSE_BODY" | jq -r '.error.code // "UNKNOWN"')
    ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error.message // "Unknown error"')
    
    echo "Error from vlayer API:" >&2
    echo "  Code: $ERROR_CODE" >&2
    echo "  Message: $ERROR_MSG" >&2
    if [ "$HTTP_CODE" != "200" ]; then
        echo "  HTTP Status: $HTTP_CODE" >&2
    fi
    
    # Output error JSON to stdout so Solidity script can parse it
    echo "{\"error\": \"$ERROR_CODE\", \"message\": $(echo "$ERROR_MSG" | jq -R .)}" >&1
    exit 1
fi

# Check HTTP status code (after checking for API errors)
if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: vlayer API returned HTTP $HTTP_CODE" >&2
    echo "Response:" >&2
    echo "$RESPONSE_BODY" | jq . >&2
    
    # Output error JSON to stdout
    ERROR_MSG="HTTP $HTTP_CODE: $(echo "$RESPONSE_BODY" | jq -r '.error.message // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")"
    echo "{\"error\": \"HTTP_ERROR\", \"message\": $(echo "$ERROR_MSG" | jq -R .)}" >&1
    exit 1
fi

# Validate success response format (per API documentation)
if ! echo "$RESPONSE_BODY" | jq -e '.success == true' > /dev/null 2>&1; then
    echo "Error: Invalid response format - missing 'success' field" >&2
    echo "Response:" >&2
    echo "$RESPONSE_BODY" | jq . >&2
    exit 1
fi

# Validate required fields in data object
if ! echo "$RESPONSE_BODY" | jq -e '.data.zkProof' > /dev/null 2>&1; then
    echo "Error: Response missing 'data.zkProof' field" >&2
    echo "Response:" >&2
    echo "$RESPONSE_BODY" | jq . >&2
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq -e '.data.journalDataAbi' > /dev/null 2>&1; then
    echo "Error: Response missing 'data.journalDataAbi' field" >&2
    echo "Response:" >&2
    echo "$RESPONSE_BODY" | jq . >&2
    exit 1
fi

# Output the response in the format expected by the Solidity script
# The Solidity script expects: { "zkProof": "...", "journalDataAbi": "..." }
# So we extract from data object and reformat
echo "$RESPONSE_BODY" | jq '{
  "zkProof": .data.zkProof,
  "journalDataAbi": .data.journalDataAbi
}'
