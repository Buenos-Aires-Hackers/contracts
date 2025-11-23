#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Set vlayer API credentials (can be overridden by .env file)
export VLAYER_CLIENT_ID="${VLAYER_CLIENT_ID:-3006e6ae-1252-4444-9f62-f991f9da02e9}"
export VLAYER_API_KEY="${VLAYER_API_KEY:-Eb1cLVBBZIcoidDWZSQ9AM53RgUJo7qLyeBcpjqbgDITb3xh4VBBJsBAXiLnnSDa}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
EVVM_GREEN='\033[38;2;1;240;148m'
NC='\033[0m' # No Color

# Banner
echo -e "${EVVM_GREEN}"
echo "░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓██████████████▓▒░  "
echo "░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ "
echo "░▒▓█▓▒░       ░▒▓█▓▒▒▓█▓▒░ ░▒▓█▓▒▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ " 
echo "░▒▓██████▓▒░  ░▒▓█▓▒▒▓█▓▒░ ░▒▓█▓▒▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ "
echo "░▒▓█▓▒░        ░▒▓█▓▓█▓▒░   ░▒▓█▓▓█▓▒░ ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ "
echo "░▒▓█▓▒░        ░▒▓█▓▓█▓▒░   ░▒▓█▓▓█▓▒░ ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ "
echo "░▒▓████████▓▒░  ░▒▓██▓▒░     ░▒▓██▓▒░  ░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░ "
echo -e "${NC}"

# Function to validate Ethereum addresses
validate_address() {
    if [[ $1 =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate numbers
validate_number() {
    if [[ $1 =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate file path
validate_file() {
    if [[ -f "$1" ]]; then
        return 0
    else
        return 1
    fi
}

# Network selection
echo -e "${GREEN}=== Network Selection ===${NC}"
echo "Available networks:"
echo "  eth    - Ethereum Sepolia"
echo "  arb    - Arbitrum Sepolia"
echo "  base   - Base Sepolia"
echo "  custom - Custom RPC URL"
echo ""

while true; do
    read -p "$(echo -e "Select network (eth/arb/base/custom) ${GRAY}[arb]${NC}: ")" network
    network=${network:-"arb"}
    
    if [[ $network == "eth" || $network == "arb" || $network == "base" || $network == "custom" ]]; then
        break
    else
        echo -e "${RED}Error: Invalid network. Use 'eth', 'arb', 'base', or 'custom'${NC}"
    fi
done

# Get wallet from environment or use default
WALLET=${WALLET:-defaultKey}

# Get the broadcaster address from the wallet account
# This ensures the shopper matches the broadcaster
BROADCASTER_ADDRESS=""

# Try multiple methods to get the address
# Method 1: cast wallet address with account name (works for non-encrypted wallets)
BROADCASTER_ADDRESS=$(cast wallet address $WALLET 2>/dev/null | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")

# Method 2: Try to find keystore file and get address (may require password)
if [[ -z "$BROADCASTER_ADDRESS" ]]; then
    KEYSTORE_DIR="$HOME/.foundry/keystores"
    if [[ -d "$KEYSTORE_DIR" ]]; then
        # Look for keystore file matching the wallet name
        KEYSTORE_FILE=$(find "$KEYSTORE_DIR" -type f -name "*$WALLET*" 2>/dev/null | head -1)
        if [[ -n "$KEYSTORE_FILE" ]]; then
            # Try without password first
            BROADCASTER_ADDRESS=$(cast wallet address --keystore "$KEYSTORE_FILE" 2>/dev/null | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
            
            # If that failed, try with password
            if [[ -z "$BROADCASTER_ADDRESS" ]]; then
                echo -e "${BLUE}Keystore requires password. Please enter password for wallet '$WALLET':${NC}"
                read -s KEYSTORE_PASSWORD
                echo ""  # New line after password input
                
                # Get private key using password, then derive address from it
                PRIVATE_KEY=$(cast wallet private-key --keystore "$KEYSTORE_FILE" --password "$KEYSTORE_PASSWORD" 2>/dev/null | grep -oE "0x[a-fA-F0-9]{64}" | head -1 || echo "")
                if [[ -n "$PRIVATE_KEY" ]]; then
                    BROADCASTER_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
                fi
                
                # Clear password from memory (best effort)
                unset KEYSTORE_PASSWORD
            fi
        fi
    fi
fi

# Method 3: Last resort - prompt user for address if we still don't have it
if [[ -z "$BROADCASTER_ADDRESS" ]]; then
    echo -e "${YELLOW}Could not automatically determine broadcaster address from wallet '$WALLET'.${NC}"
    echo -e "${BLUE}Please enter your broadcaster address (the address used with --account $WALLET):${NC}"
    while true; do
        read -p "Broadcaster address (0x...): " BROADCASTER_ADDRESS
        if validate_address "$BROADCASTER_ADDRESS"; then
            break
        else
            echo -e "${RED}Error: Invalid address. Must be a valid Ethereum address (0x + 40 hex characters)${NC}"
        fi
    done
fi

echo -e "${GREEN}Broadcaster address: $BROADCASTER_ADDRESS${NC}"

# Set RPC URL and network args based on selection
if [[ $network == "custom" ]]; then
    echo -e "${BLUE}=== Custom Network Configuration ===${NC}"
    while true; do
        read -p "Enter RPC URL: " rpc_url
        if [[ -n "$rpc_url" ]]; then
            break
        else
            echo -e "${RED}Error: RPC URL is required${NC}"
        fi
    done
    NETWORK_ARGS="--rpc-url $rpc_url --account $WALLET --broadcast"
else
    # Use makefile network args
    if [[ $network == "eth" ]]; then
        NETWORK_ARGS="--rpc-url $RPC_URL_ETH_SEPOLIA --account $WALLET --broadcast --verify --etherscan-api-key $ETHERSCAN_API"
    elif [[ $network == "arb" ]]; then
        NETWORK_ARGS="--rpc-url $RPC_URL_ARB_SEPOLIA --account $WALLET --broadcast --verify --etherscan-api-key $ETHERSCAN_API"
    elif [[ $network == "base" ]]; then
        NETWORK_ARGS="--rpc-url https://sepolia.base.org --chain-id 84532 --account $WALLET --broadcast --verify --etherscan-api-key $ETHERSCAN_API --via-ir"
    fi
fi

echo -e "\n${GREEN}=== Listing Configuration ===${NC}"

# Get listing URL
read -p "$(echo -e "Listing URL ${GRAY}[https://test-1111111111111111111111111111111111711111111111125595.myshopify.com/admin/api/2024-01/orders/16447065227633.json]${NC}: ")" listing_url
listing_url=${listing_url:-"https://test-1111111111111111111111111111111111711111111111125595.myshopify.com/admin/api/2024-01/orders/16447065227633.json"}

# Get listing amount
while true; do
    read -p "$(echo -e "Listing Amount (in smallest unit, e.g., 100000000 for 100 USDC) ${GRAY}[100000000]${NC}: ")" listing_amount
    listing_amount=${listing_amount:-"100000000"}
    if validate_number "$listing_amount"; then
        break
    else
        echo -e "${RED}Error: Must be a valid number${NC}"
    fi
done

# Get shopper address
while true; do
    read -p "$(echo -e "Shopper Address (0x...) ${GRAY}[msg.sender]${NC}: ")" shopper_address
    if [[ -z "$shopper_address" ]]; then
        shopper_address=""
        break
    elif validate_address "$shopper_address"; then
        break
    else
        echo -e "${RED}Error: Invalid address. Must be a valid Ethereum address (0x + 40 hex characters)${NC}"
    fi
done

# Get private credentials configuration
echo -e "\n${BLUE}=== Private Credentials Configuration ===${NC}"
read -p "$(echo -e "Do you want to provide private credentials directly (hex) or compute from raw data? (direct/raw) ${GRAY}[raw]${NC}: ")" creds_mode
creds_mode=${creds_mode:-"raw"}

if [[ $creds_mode == "direct" ]]; then
    while true; do
        read -p "Private Credentials (bytes32 hex, 0x...): " private_credentials
        if [[ $private_credentials =~ ^0x[a-fA-F0-9]{64}$ ]]; then
            break
        else
            echo -e "${RED}Error: Invalid bytes32. Must be 0x + 64 hex characters${NC}"
        fi
    done
else
    echo -e "${YELLOW}Enter raw credential data:${NC}"
    read -p "$(echo -e "Full Name ${GRAY}[John Doe]${NC}: ")" full_name
    full_name=${full_name:-"John Doe"}
    
    read -p "$(echo -e "Email Address ${GRAY}[john@example.com]${NC}: ")" email_address
    email_address=${email_address:-"john@example.com"}
    
    read -p "$(echo -e "Home Address ${GRAY}[123 Main St]${NC}: ")" home_address
    home_address=${home_address:-"123 Main St"}
    
    read -p "$(echo -e "City ${GRAY}[New York]${NC}: ")" city
    city=${city:-"New York"}
    
    read -p "$(echo -e "Country ${GRAY}[USA]${NC}: ")" country
    country=${country:-"USA"}
    
    read -p "$(echo -e "ZIP Code ${GRAY}[10001]${NC}: ")" zip
    zip=${zip:-"10001"}
fi

# Show listing summary
echo -e "\n${YELLOW}=== Listing Summary ===${NC}"
echo -e "Network: ${GREEN}$network${NC}"
echo -e "Listing URL: ${GREEN}$listing_url${NC}"
echo -e "Listing Amount: ${GREEN}$listing_amount${NC}"
if [[ -n "$shopper_address" ]]; then
    echo -e "Shopper Address: ${GREEN}$shopper_address${NC}"
else
    echo -e "Shopper Address: ${GRAY}msg.sender${NC}"
fi
if [[ $creds_mode == "direct" ]]; then
    echo -e "Private Credentials: ${GREEN}$private_credentials${NC}"
else
    echo -e "Full Name: ${GREEN}$full_name${NC}"
    echo -e "Email: ${GREEN}$email_address${NC}"
    echo -e "Address: ${GREEN}$home_address${NC}"
    echo -e "City: ${GREEN}$city${NC}"
    echo -e "Country: ${GREEN}$country${NC}"
    echo -e "ZIP: ${GREEN}$zip${NC}"
fi

echo ""
read -p "Proceed with listing creation? (y/n): " confirm_listing

if [[ $confirm_listing != "y" && $confirm_listing != "Y" ]]; then
    echo -e "${RED}Listing creation cancelled.${NC}"
    exit 1
fi

# Set environment variables for List.s.sol
export LISTING_URL="$listing_url"
export LISTING_AMOUNT="$listing_amount"

# Set shopper address - use provided address, or default to broadcaster address
if [[ -n "$shopper_address" ]]; then
    export SHOPPER_ADDRESS="$shopper_address"
elif [[ -n "$BROADCASTER_ADDRESS" ]]; then
    export SHOPPER_ADDRESS="$BROADCASTER_ADDRESS"
    echo -e "${GREEN}Using broadcaster address as shopper: $BROADCASTER_ADDRESS${NC}"
else
    echo -e "${RED}Error: Could not determine broadcaster address and no shopper address provided.${NC}"
    echo -e "${YELLOW}Please either:${NC}"
    echo -e "${YELLOW}  1. Provide a shopper address when prompted${NC}"
    echo -e "${YELLOW}  2. Ensure your wallet '$WALLET' is accessible via 'cast wallet address $WALLET'${NC}"
    echo -e "${YELLOW}  3. Set SHOPPER_ADDRESS environment variable manually${NC}"
    exit 1
fi

if [[ $creds_mode == "direct" ]]; then
    export PRIVATE_CREDENTIALS="$private_credentials"
else
    export FULL_NAME="$full_name"
    export EMAIL_ADDRESS="$email_address"
    export HOME_ADDRESS="$home_address"
    export CITY="$city"
    export COUNTRY="$country"
    export ZIP="$zip"
fi

# Run List.s.sol
echo -e "\n${BLUE}=== Creating Listing ===${NC}"
forge script script/List.s.sol:List $NETWORK_ARGS -vvvvvv

if [ $? -ne 0 ]; then
    echo -e "${RED}Listing creation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Listing created successfully!${NC}"

# Ask if they want to submit purchase
echo ""
read -p "Do you want to submit a purchase now? (y/n): " submit_purchase

if [[ $submit_purchase != "y" && $submit_purchase != "Y" ]]; then
    echo -e "${YELLOW}To submit purchase later, run:${NC}"
    echo -e "  ${YELLOW}forge script script/SubmitPurchaseWithWebProof.s.sol:SubmitPurchaseWithWebProof $NETWORK_ARGS -vvvvvv${NC}"
    echo -e "${GREEN}Listing and purchase workflow completed!${NC}"
    exit 0
fi

# Purchase configuration
echo -e "\n${GREEN}=== Purchase Configuration ===${NC}"

# Get web proof path or URL - automatically use default if not provided via environment
# Priority: 1) WEB_PROOF_PATH env var, 2) Use listing URL to generate proof, 3) script/examples/example_web_proof.json, 4) web_proof.json in current dir
web_proof_path=""
if [[ -n "$WEB_PROOF_PATH" ]]; then
    # Check if it's a URL or file
    if [[ "$WEB_PROOF_PATH" =~ ^https?:// ]]; then
        web_proof_path="$WEB_PROOF_PATH"
        echo -e "${GREEN}Using URL to generate web proof: $web_proof_path${NC}"
    elif validate_file "$WEB_PROOF_PATH"; then
        web_proof_path="$WEB_PROOF_PATH"
        echo -e "${GREEN}Using web proof from WEB_PROOF_PATH: $web_proof_path${NC}"
    fi
fi

# If not set, try to use listing URL from latest listing
if [[ -z "$web_proof_path" ]]; then
    LISTING_FILE="deployments/84532/Listings/latest_listing.json"
    if [[ -f "$LISTING_FILE" ]]; then
        LISTING_URL=$(jq -r '.url' "$LISTING_FILE" 2>/dev/null || echo "")
        if [[ -n "$LISTING_URL" && "$LISTING_URL" != "null" ]]; then
            web_proof_path="$LISTING_URL"
            echo -e "${GREEN}Using listing URL to generate web proof: $web_proof_path${NC}"
        fi
    fi
fi

# Fallback to example file or web_proof.json
if [[ -z "$web_proof_path" ]]; then
    if [[ -f "script/examples/example_web_proof.json" ]]; then
        web_proof_path="script/examples/example_web_proof.json"
        echo -e "${YELLOW}Using example web proof file (will generate from URL if it contains one): $web_proof_path${NC}"
    elif [[ -f "web_proof.json" ]]; then
        web_proof_path="web_proof.json"
        echo -e "${GREEN}Using web proof from current directory: $web_proof_path${NC}"
    else
        echo -e "${RED}Error: No web proof file or URL found.${NC}"
        echo -e "${YELLOW}Please either:${NC}"
        echo -e "${YELLOW}  1. Set WEB_PROOF_PATH to a URL or file path${NC}"
        echo -e "${YELLOW}  2. Place a web_proof.json file in the current directory${NC}"
        echo -e "${YELLOW}  3. Ensure a listing exists with a URL${NC}"
        exit 1
    fi
fi

# Get shipping state
while true; do
    read -p "$(echo -e "Shipping State (0=PENDING, 1=SHIPPED, 2=IN_TRANSIT, 3=DELIVERED) ${GRAY}[3]${NC}: ")" shipping_state
    shipping_state=${shipping_state:-"3"}
    if [[ $shipping_state =~ ^[0-3]$ ]]; then
        break
    else
        echo -e "${RED}Error: Must be a number between 0 and 3${NC}"
    fi
done

# Get extraction queries (must match Treasury's EXPECTED_QUERIES_HASH)
# First, read the expected queries hash from the Treasury contract
echo -e "\n${BLUE}=== Reading Treasury Configuration ===${NC}"

# Determine chain ID from network
CHAIN_ID=""
if [[ $network == "base" ]]; then
    CHAIN_ID="84532"
elif [[ $network == "eth" ]]; then
    CHAIN_ID="11155111"
elif [[ $network == "arb" ]]; then
    CHAIN_ID="421614"
elif [[ $network == "custom" ]]; then
    # Try to extract chain ID from RPC URL or use default
    CHAIN_ID="${CHAIN_ID:-84532}"
fi

# Read Treasury address from deployments.json
DEPLOYMENTS_FILE="deployments/${CHAIN_ID}/deployments.json"
TREASURY_ADDRESS=""
if [[ -f "$DEPLOYMENTS_FILE" ]]; then
    TREASURY_ADDRESS=$(jq -r '.treasury' "$DEPLOYMENTS_FILE" 2>/dev/null || echo "")
    if [[ -n "$TREASURY_ADDRESS" && "$TREASURY_ADDRESS" != "null" && "$TREASURY_ADDRESS" != "" ]]; then
        echo -e "${GREEN}Treasury address: $TREASURY_ADDRESS${NC}"
        
        # Get RPC URL for the network
        RPC_URL_FOR_CAST=""
        if [[ $network == "base" ]]; then
            RPC_URL_FOR_CAST="https://sepolia.base.org"
        elif [[ $network == "eth" ]]; then
            RPC_URL_FOR_CAST="${RPC_URL_ETH_SEPOLIA:-https://rpc.sepolia.org}"
        elif [[ $network == "arb" ]]; then
            RPC_URL_FOR_CAST="${RPC_URL_ARB_SEPOLIA:-https://sepolia-rollup.arbitrum.io/rpc}"
        elif [[ $network == "custom" ]]; then
            RPC_URL_FOR_CAST="$rpc_url"
        fi
        
        # Read EXPECTED_QUERIES_HASH from Treasury contract
        if [[ -n "$RPC_URL_FOR_CAST" ]]; then
            echo -e "${BLUE}Reading EXPECTED_QUERIES_HASH from Treasury contract...${NC}"
            EXPECTED_QUERIES_HASH=$(cast call "$TREASURY_ADDRESS" "EXPECTED_QUERIES_HASH()(bytes32)" --rpc-url "$RPC_URL_FOR_CAST" 2>/dev/null || echo "")
            
            if [[ -n "$EXPECTED_QUERIES_HASH" && "$EXPECTED_QUERIES_HASH" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
                echo -e "${GREEN}Expected Queries Hash from Treasury:${NC} ${YELLOW}$EXPECTED_QUERIES_HASH${NC}"
                echo -e "${YELLOW}⚠️  Your extraction queries must produce this exact queries hash when processed by vlayer.${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not read EXPECTED_QUERIES_HASH from contract. Continuing anyway...${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  RPC URL not available. Cannot read EXPECTED_QUERIES_HASH from contract.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Treasury address not found in $DEPLOYMENTS_FILE${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Deployments file not found: $DEPLOYMENTS_FILE${NC}"
    echo -e "${YELLOW}   Cannot read EXPECTED_QUERIES_HASH from contract.${NC}"
fi

# IMPORTANT: The extraction queries MUST match exactly what was used during Treasury deployment.
# The queries hash is computed by vlayer from this JSON, and any difference in format will cause a mismatch.
# Default to Shopify order fulfillment status only
DEFAULT_QUERIES='{"response.body": {"jmespath": ["order.fulfillment_status"]}}'
echo -e "\n${BLUE}=== Extraction Queries Configuration ===${NC}"
if [[ -n "$EXPECTED_QUERIES_HASH" && "$EXPECTED_QUERIES_HASH" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo -e "${YELLOW}Target queries hash: $EXPECTED_QUERIES_HASH${NC}"
fi
echo -ne "Extraction Queries (JSON) ${GRAY}[default: order.fulfillment_status]${NC}: "
read extraction_queries
extraction_queries=${extraction_queries:-$DEFAULT_QUERIES}

# Normalize the JSON to ensure consistent formatting (important for queries hash)
if ! echo "$extraction_queries" | jq . > /dev/null 2>&1; then
    echo -e "${RED}Error: Invalid JSON format for extraction queries${NC}"
    exit 1
fi

# Normalize JSON (removes whitespace differences, ensures consistent key order)
extraction_queries=$(echo "$extraction_queries" | jq -c .)

# Convert old format to new format if needed
if echo "$extraction_queries" | jq -e '.["response.body"] | type == "array"' > /dev/null 2>&1; then
    extraction_queries=$(echo "$extraction_queries" | jq -c '{
      "response.body": {
        "jmespath": (.["response.body"] | map(.["jmespath"]))
      }
    }')
    echo -e "${YELLOW}Converted extraction queries to new format${NC}"
fi

# Final normalization to ensure consistent format
extraction_queries=$(echo "$extraction_queries" | jq -c .)

# Get listing file (optional)
read -p "$(echo -e "Listing File Path (leave empty to use latest) ${GRAY}[]${NC}: ")" listing_file

# Show purchase summary
echo -e "\n${YELLOW}=== Purchase Summary ===${NC}"
echo -e "Web Proof Path: ${GREEN}$web_proof_path${NC}"
echo -e "Shipping State: ${GREEN}$shipping_state${NC}"
echo -e "Extraction Queries: ${GREEN}$extraction_queries${NC}"
if [[ -n "$EXPECTED_QUERIES_HASH" && "$EXPECTED_QUERIES_HASH" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo -e "Expected Queries Hash: ${YELLOW}$EXPECTED_QUERIES_HASH${NC}"
    echo -e "${YELLOW}⚠️  The web proof must produce this exact queries hash.${NC}"
fi
if [[ -n "$listing_file" ]]; then
    echo -e "Listing File: ${GREEN}$listing_file${NC}"
else
    echo -e "Listing File: ${GRAY}latest_listing.json${NC}"
fi

echo ""
read -p "Proceed with purchase submission? (y/n): " confirm_purchase

if [[ $confirm_purchase != "y" && $confirm_purchase != "Y" ]]; then
    echo -e "${RED}Purchase submission cancelled.${NC}"
    exit 1
fi

# Set environment variables for SubmitPurchaseWithWebProof.s.sol
# Note: WEB_PROOF_PATH is no longer needed - script uses listing URL automatically
export SHIPPING_STATE="$shipping_state"
export EXTRACTION_QUERIES="$extraction_queries"
if [[ -n "$listing_file" ]]; then
    export LISTING_FILE="$listing_file"
fi

# Run SubmitPurchaseWithWebProof.s.sol
echo -e "\n${BLUE}=== Submitting Purchase ===${NC}"
forge script script/SubmitPurchaseWithWebProof.s.sol:SubmitPurchaseWithWebProof $NETWORK_ARGS -vvvvvv

if [ $? -ne 0 ]; then
    echo -e "${RED}Purchase submission failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Purchase submitted successfully!${NC}"
echo -e "${GREEN}Listing and purchase workflow completed!${NC}"

