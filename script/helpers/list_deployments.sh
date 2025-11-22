#!/bin/bash

# Script to list all saved deployments and listings
# Usage: ./list_deployments.sh [chain_id]

CHAIN_ID=${1:-84532}  # Default to Base Sepolia
DEPLOYMENTS_DIR="deployments/$CHAIN_ID"

if [ ! -d "$DEPLOYMENTS_DIR" ]; then
    echo "No deployments found for chain ID: $CHAIN_ID"
    echo "Directory does not exist: $DEPLOYMENTS_DIR"
    exit 1
fi

echo "====================================="
echo "Deployments for Chain ID: $CHAIN_ID"
echo "====================================="

# Show deployment addresses
if [ -f "$DEPLOYMENTS_DIR/deployments.json" ]; then
    echo ""
    echo "Deployment Addresses:"
    if command -v jq &> /dev/null; then
        echo "  Staking:     $(jq -r '.staking' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  Evvm:        $(jq -r '.evvm' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  Estimator:   $(jq -r '.estimator' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  NameService: $(jq -r '.nameService' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  Treasury:    $(jq -r '.treasury' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  P2PSwap:     $(jq -r '.p2pSwap' "$DEPLOYMENTS_DIR/deployments.json")"
        echo "  USDC:        $(jq -r '.paymentToken' "$DEPLOYMENTS_DIR/deployments.json")"
    else
        cat "$DEPLOYMENTS_DIR/deployments.json"
    fi
elif [ -f "$DEPLOYMENTS_DIR/Treasury/address.json" ]; then
    echo ""
    if command -v jq &> /dev/null; then
        TREASURY_ADDRESS=$(jq -r '.address' "$DEPLOYMENTS_DIR/Treasury/address.json")
        echo "Treasury Address: $TREASURY_ADDRESS"
    else
        echo "Treasury data:"
        cat "$DEPLOYMENTS_DIR/Treasury/address.json"
    fi
fi

# Show all listings
LISTINGS_DIR="$DEPLOYMENTS_DIR/Listings"
if [ -d "$LISTINGS_DIR" ]; then
    LISTING_COUNT=$(find "$LISTINGS_DIR" -name "listing_*.json" | wc -l | tr -d ' ')
    echo ""
    echo "Total Listings: $LISTING_COUNT"
    echo "-----------------------------------"

    if [ "$LISTING_COUNT" -gt 0 ]; then
        echo ""
        echo "Recent Listings:"
        find "$LISTINGS_DIR" -name "listing_*.json" -type f | sort -r | head -5 | while read -r file; do
            echo ""
            echo "File: $(basename "$file")"
            if command -v jq &> /dev/null; then
                LISTING_ID=$(jq -r '.listingId' "$file")
                AMOUNT=$(jq -r '.amount' "$file")
                SHOPPER=$(jq -r '.shopper' "$file")
                TIMESTAMP=$(jq -r '.timestamp' "$file")
                echo "  Listing ID: $LISTING_ID"
                echo "  Amount: $AMOUNT"
                echo "  Shopper: $SHOPPER"
                echo "  Timestamp: $TIMESTAMP"
            else
                cat "$file"
            fi
        done
    fi

    # Show latest listing
    if [ -f "$LISTINGS_DIR/latest_listing.json" ]; then
        echo ""
        echo "-----------------------------------"
        echo "Latest Listing:"
        if command -v jq &> /dev/null; then
            jq '.' "$LISTINGS_DIR/latest_listing.json"
        else
            cat "$LISTINGS_DIR/latest_listing.json"
        fi
    fi
fi

# Show all purchases
PURCHASES_DIR="$DEPLOYMENTS_DIR/Purchases"
if [ -d "$PURCHASES_DIR" ]; then
    PURCHASE_COUNT=$(find "$PURCHASES_DIR" -name "purchase_*.json" | wc -l | tr -d ' ')
    echo ""
    echo "====================================="
    echo "Total Purchases: $PURCHASE_COUNT"
    echo "-----------------------------------"

    if [ "$PURCHASE_COUNT" -gt 0 ]; then
        echo ""
        echo "Recent Purchases:"
        find "$PURCHASES_DIR" -name "purchase_*.json" -type f | sort -r | head -5 | while read -r file; do
            echo ""
            echo "File: $(basename "$file")"
            if command -v jq &> /dev/null; then
                LISTING_ID=$(jq -r '.listingId' "$file")
                MERCHANT=$(jq -r '.merchant' "$file")
                AMOUNT=$(jq -r '.amount' "$file")
                TIMESTAMP=$(jq -r '.timestamp' "$file")
                echo "  Listing ID: $LISTING_ID"
                echo "  Merchant: $MERCHANT"
                echo "  Amount: $AMOUNT"
                echo "  Timestamp: $TIMESTAMP"
            else
                cat "$file"
            fi
        done
    fi
fi

echo ""
echo "====================================="
