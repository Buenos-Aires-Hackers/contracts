#!/bin/bash

# Script to get a specific listing by ID or get the latest listing
# Usage: ./get_listing.sh [listing_id] [chain_id]

CHAIN_ID=${2:-84532}  # Default to Base Sepolia
DEPLOYMENTS_DIR="deployments/$CHAIN_ID"
LISTINGS_DIR="$DEPLOYMENTS_DIR/Listings"

if [ ! -d "$LISTINGS_DIR" ]; then
    echo "No listings found for chain ID: $CHAIN_ID"
    exit 1
fi

if [ -z "$1" ]; then
    # No listing ID provided, show latest
    if [ -f "$LISTINGS_DIR/latest_listing.json" ]; then
        echo "Latest listing:"
        cat "$LISTINGS_DIR/latest_listing.json"
    else
        echo "No latest listing found"
        exit 1
    fi
else
    # Search for listing by ID
    LISTING_ID=$1
    FOUND=false

    for file in "$LISTINGS_DIR"/listing_*.json; do
        if [ -f "$file" ]; then
            if command -v jq &> /dev/null; then
                FILE_LISTING_ID=$(jq -r '.listingId' "$file")
                if [ "$FILE_LISTING_ID" = "$LISTING_ID" ]; then
                    cat "$file"
                    FOUND=true
                    break
                fi
            else
                # Without jq, just search for the listing ID in the file
                if grep -q "$LISTING_ID" "$file"; then
                    cat "$file"
                    FOUND=true
                    break
                fi
            fi
        fi
    done

    if [ "$FOUND" = false ]; then
        echo "Listing not found: $LISTING_ID"
        exit 1
    fi
fi
