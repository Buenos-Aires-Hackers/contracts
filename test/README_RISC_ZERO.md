# Testing with RISC Zero Proofs

This document explains how to test the Treasury contract with real RISC Zero proofs instead of mocks.

## Overview

The codebase has been updated to use the real RISC Zero Verifier Router deployed on Base Sepolia. Tests that require successful proof verification need to use real ZK proofs generated from your zkVM program.

## Two Approaches

### 1. Using FFI to Generate Proofs During Tests (Recommended for Development)

This approach uses the `RiscZeroCheats` contract from RISC Zero to generate proofs on-the-fly during test execution.

**Requirements:**
- Rust toolchain installed
- RISC Zero dependencies available in `lib/risc0-ethereum`
- Your zkVM program compiled to ELF format

**Usage:**

```solidity
import {RiscZeroTestHelper} from "../helpers/RiscZeroTestHelper.sol";

contract MyTest is BaseTest, RiscZeroTestHelper {
    function testWithRealProof() public {
        bytes memory input = abi.encode(...);
        (bytes memory journal, bytes memory seal) = generateProof("path/to/program.elf", input);
        
        // Use seal in your test
        treasury.submitPurchase(listingId, purchaseData, seal);
    }
}
```

**See:** `test/unit/TreasuryWithRealProofs.t.sol.example` for a complete example.

### 2. Using Pre-generated Test Receipts (Recommended for CI/CD)

This approach uses hardcoded seals and journals that were generated offline. This is faster and doesn't require Rust during test execution.

**How to generate a test receipt:**

1. Write your zkVM program in Rust
2. Compile it to ELF format
3. Generate a proof offline using RISC Zero tools
4. Extract the seal and journal
5. Create a `TestReceipt` library similar to RISC Zero's test files

**Example TestReceipt structure:**

```solidity
library TestReceipt {
    bytes public constant SEAL = hex"..."; // Your proof seal
    bytes public constant JOURNAL = hex"..."; // Your journal output
    bytes32 public constant IMAGE_ID = hex"..."; // Your program's image ID
}
```

**Usage:**

```solidity
import {TestReceipt} from "./TestReceipt.sol";

contract MyTest is BaseTest {
    function testWithPreGeneratedProof() public {
        bytes memory seal = TestReceipt.SEAL;
        bytes memory journal = TestReceipt.JOURNAL;
        bytes32 imageId = TestReceipt.IMAGE_ID;
        
        // Use in your test
        treasury.submitPurchase(listingId, purchaseData, seal);
    }
}
```

## Current Test Status

Most tests in `Treasury.t.sol` currently use fake seals and expect reverts. To make them pass with real proofs:

1. **Option A:** Generate real proofs and replace the fake seals
2. **Option B:** Keep the tests as-is (they verify that invalid proofs are rejected)
3. **Option C:** Create separate test files for tests that need real proofs

## Configuration

### Base Sepolia Verifier

The verifier router address is configured in `script/NetworkConfig.sol`:
- Address: `0x0b144E07A0826182B6b59788c34b32Bfa86Fb711`
- This is the recommended verifier as it routes to appropriate verifiers based on proof version

### RISC Zero Constants

Update these constants in `test/helpers/BaseTest.sol` with your actual values:
- `RISC0_IMAGE_ID` - Your zkVM program's image ID
- `RISC0_NOTARY_KEY_FINGERPRINT` - Expected notary key fingerprint from vlayer
- `RISC0_QUERIES_HASH` - Expected queries hash for your JMESPath queries

## References

- [RISC Zero Verifier Contracts Documentation](https://dev.risczero.com/api/blockchain-integration/contracts/verifier)
- [RISC Zero Ethereum Contracts Tests](https://github.com/risc0/risc0-ethereum/tree/main/contracts/test)
- [RISC Zero Cheats Documentation](https://github.com/risc0/risc0-ethereum/blob/main/contracts/src/test/RiscZeroCheats.sol)

## Example: Generating a Proof

If you're using the FFI approach, here's how to generate a proof:

```bash
# Set up your zkVM program
cd your-zkvm-program
cargo build --release

# The prove() function in RiscZeroTestHelper will call:
# cargo run --manifest-path lib/risc0-ethereum/crates/ffi/Cargo.toml \
#   --bin risc0-forge-ffi prove target/riscv32im-risc0-zkvm-elf/release/your_program <hex-encoded-input>
```

## Troubleshooting

### "Selector mismatch" error
- Make sure your proof was generated with the correct RISC Zero version
- Check that you're using the correct verifier (router vs direct verifier)

### "Verification failed" error
- Verify your image ID matches the one used to generate the proof
- Check that the journal hash matches what's expected
- Ensure your proof wasn't corrupted

### FFI errors
- Make sure Rust toolchain is installed
- Verify RISC Zero dependencies are available
- Check that your ELF path is correct

