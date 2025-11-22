#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

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
read -p "$(echo -e "Listing URL ${GRAY}[https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234]${NC}: ")" listing_url
listing_url=${listing_url:-"https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234"}

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
if [[ -n "$shopper_address" ]]; then
    export SHOPPER_ADDRESS="$shopper_address"
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

# Get web proof path
while true; do
    read -p "Web Proof File Path: " web_proof_path
    if validate_file "$web_proof_path"; then
        break
    else
        echo -e "${RED}Error: File does not exist. Please provide a valid file path.${NC}"
    fi
done

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

# Get extraction queries
read -p "$(echo -e "Extraction Queries (JSON) ${GRAY}[{\"response.body\": [{\"jmespath\": \"orderStatus\"}]}]${NC}: ")" extraction_queries
extraction_queries=${extraction_queries:-'{"response.body": [{"jmespath": "orderStatus"}]}'}

# Get listing file (optional)
read -p "$(echo -e "Listing File Path (leave empty to use latest) ${GRAY}[]${NC}: ")" listing_file

# Show purchase summary
echo -e "\n${YELLOW}=== Purchase Summary ===${NC}"
echo -e "Web Proof Path: ${GREEN}$web_proof_path${NC}"
echo -e "Shipping State: ${GREEN}$shipping_state${NC}"
echo -e "Extraction Queries: ${GREEN}$extraction_queries${NC}"
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
export WEB_PROOF_PATH="$web_proof_path"
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

