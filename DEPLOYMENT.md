# Deployment Guide for Base Sepolia

This guide explains how to deploy the CypherMarket contracts to Base Sepolia testnet.

## Prerequisites

### 1. Get Base Sepolia ETH

You need testnet ETH for gas fees. Get it from:
- **Coinbase Faucet**: https://www.coinbase.com/faucets/base-ethereum-goerli-faucet
- **Bridge from Ethereum Sepolia**: https://bridge.base.org/deposit
- **Base Sepolia Faucet**: https://www.alchemy.com/faucets/base-sepolia

### 2. Set Up Environment Variables

Create a `.env` file in the project root or export these variables:

```bash
# Required for deployment
export PRIVATE_KEY="your_private_key_here"  # Private key of deployer wallet
export RISC0_IMAGE_ID="0x..."  # Your zkVM program's image ID
export RISC0_NOTARY_KEY_FINGERPRINT="0x..."  # From vlayer
export RISC0_QUERIES_HASH="0x..."  # Hash of your JMESPath queries
export PAYMENT_TOKEN_ADDRESS="0x..."  # ERC20 token address for payments

# Optional (for contract verification)
export ETHERSCAN_API_KEY="your_basescan_api_key"  # Get from https://basescan.org/apis
```

**Important**: Never commit your `.env` file or private keys to version control!

### 3. Configure Input Files

Ensure your `input/` directory has the required JSON files:

**input/address.json**:
```json
{
  "admin": "0xYourAdminAddress",
  "goldenFisher": "0xYourGoldenFisherAddress",
  "activator": "0xYourActivatorAddress"
}
```

**input/evvmBasicMetadata.json**:
```json
{
  "EvvmName": "CypherMarket",
  "principalTokenName": "CypherMarket Token",
  "principalTokenSymbol": "CYPHER"
}
```

**input/evvmAdvancedMetadata.json**:
```json
{
  "totalSupply": "2033333333000000000000000000",
  "eraTokens": "1016666666500000000000000000",
  "reward": "5000000000000000000"
}
```

## Deployment Methods

### Method 1: Using Makefile (Recommended)

```bash
# Set environment variables
export PRIVATE_KEY="your_private_key"
export RISC0_IMAGE_ID="0x..."
export RISC0_NOTARY_KEY_FINGERPRINT="0x..."
export RISC0_QUERIES_HASH="0x..."
export PAYMENT_TOKEN_ADDRESS="0x..."
export ETHERSCAN_API_KEY="your_api_key"  # Optional

# Deploy
make deployTestnet NETWORK=base
```

### Method 2: Using Foundry Script Directly

```bash
forge script script/DeployTestnet.s.sol:DeployTestnet \
    --rpc-url https://sepolia.base.org \
    --chain-id 84532 \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

### Method 3: Using Foundry Account (Alternative)

If you've set up Foundry accounts:

```bash
forge script script/DeployTestnet.s.sol:DeployTestnet \
    --rpc-url https://sepolia.base.org \
    --chain-id 84532 \
    --account defaultKey \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

## Step-by-Step Deployment

### Step 1: Verify Your Wallet Has ETH

```bash
# Check balance
cast balance <your_address> --rpc-url https://sepolia.base.org
```

You need at least 0.01 ETH for deployment.

### Step 2: Verify Environment Variables

```bash
# Check that all required variables are set
echo $RISC0_IMAGE_ID
echo $RISC0_NOTARY_KEY_FINGERPRINT
echo $RISC0_QUERIES_HASH
echo $PAYMENT_TOKEN_ADDRESS
echo $PRIVATE_KEY  # Be careful with this one!
```

### Step 3: Deploy

```bash
make deployTestnet NETWORK=base
```

The script will:
1. Verify you're on Base Sepolia (chain ID 84532)
2. Read configuration from `input/` files
3. Read RISC Zero config from environment variables
4. Deploy all contracts in the correct order
5. Set up contract relationships
6. Verify contracts on Basescan (if API key provided)

### Step 4: Save Deployment Addresses

After successful deployment, the script outputs all contract addresses. Save them:

```bash
# Example output
STAKING_ADDRESS=0x...
EVVM_ADDRESS=0x...
ESTIMATOR_ADDRESS=0x...
NAMESERVICE_ADDRESS=0x...
TREASURY_ADDRESS=0x...
P2PSWAP_ADDRESS=0x...
```

## Payment Token Setup

You need an ERC20 token address for the payment token. Options:

### Option A: Deploy Your Own Token

Deploy a simple ERC20 token first, then use its address:

```solidity
// Deploy a test token
// Then set: export PAYMENT_TOKEN_ADDRESS="0x..."
```

### Option B: Use Existing Testnet Token

If there's a testnet USDC or other token on Base Sepolia, you can use that address.

## RISC Zero Configuration

You need these values from your zkVM program setup:

1. **RISC0_IMAGE_ID**: The image ID of your compiled zkVM program
   - Generated when you compile your RISC Zero program
   - Format: `0x...` (32 bytes, hex-encoded)

2. **RISC0_NOTARY_KEY_FINGERPRINT**: The notary key fingerprint from vlayer
   - Provided by your vlayer integration
   - Format: `0x...` (32 bytes, hex-encoded)

3. **RISC0_QUERIES_HASH**: Hash of your JMESPath queries
   - Computed from the queries used to extract data
   - Format: `0x...` (32 bytes, hex-encoded)

## Verification

After deployment, verify contracts on Basescan:
- Basescan Sepolia: https://sepolia.basescan.org/

The `--verify` flag will automatically verify contracts if you provide an API key.

## Troubleshooting

### Error: "Must deploy to Base Sepolia (chain ID 84532)"
- Ensure you're using the correct RPC URL: `https://sepolia.base.org`
- Check that chain ID is 84532

### Error: "Environment variable not set"
- Make sure all required environment variables are exported
- Variable names are case-sensitive
- Check with: `env | grep RISC0`

### Error: "Insufficient funds"
- Get Base Sepolia ETH from faucet
- Check balance: `cast balance <address> --rpc-url https://sepolia.base.org`

### Error: "RPC rate limit"
- Use a private RPC endpoint (Alchemy, Infura, QuickNode)
- Or wait and retry

### Error: "File not found" (input files)
- Ensure `input/address.json`, `input/evvmBasicMetadata.json`, and `input/evvmAdvancedMetadata.json` exist
- Check file paths are correct

## Post-Deployment Checklist

- [ ] All contracts deployed successfully
- [ ] Contract addresses saved
- [ ] Contracts verified on Basescan
- [ ] Treasury configured with correct RISC Zero parameters
- [ ] Payment token address set correctly
- [ ] Test a deposit to verify everything works

## Example Deployment Command

```bash
# Full example with all variables
export PRIVATE_KEY="0x..."
export RISC0_IMAGE_ID="0x11d264ed8dfdee222b820f0278e4d7f55d4b69a5472253a471c102265a91ea1a"
export RISC0_NOTARY_KEY_FINGERPRINT="0x..."
export RISC0_QUERIES_HASH="0x..."
export PAYMENT_TOKEN_ADDRESS="0x..."
export ETHERSCAN_API_KEY="..."

make deployTestnet NETWORK=base
```

## Security Notes

1. **Never commit private keys** to version control
2. **Use separate wallets** for testnet vs mainnet
3. **Verify all addresses** before using in production
4. **Double-check RISC Zero parameters** - incorrect values will break verification
5. **Test thoroughly** on testnet before mainnet deployment
