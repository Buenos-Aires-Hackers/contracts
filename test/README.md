# CypherMarket Test Suite

Comprehensive Foundry test suite for the CypherMarket smart contracts.

## Overview

This test suite provides extensive coverage for all core contracts including:
- Treasury contract (with RISC Zero verification)
- Evvm core contract
- Staking system
- NameService
- P2PSwap exchange
- Integration tests for multi-contract interactions

## Structure

```
test/
├── helpers/
│   └── BaseTest.sol           # Base test contract with common setup
├── mocks/
│   ├── MockERC20.sol          # ERC20 token mock for testing
│   └── MockRiscZeroVerifier.sol # RISC Zero verifier mock
├── unit/
│   ├── Treasury.t.sol         # Treasury contract tests (WORKING)
│   ├── Evvm.t.sol.wip        # Evvm contract tests (IN PROGRESS)
│   ├── Staking.t.sol.wip     # Staking contract tests (IN PROGRESS)
│   ├── NameService.t.sol.wip # NameService tests (IN PROGRESS)
│   └── P2PSwap.t.sol.wip     # P2PSwap tests (IN PROGRESS)
├── integration/
│   └── Integration.t.sol.wip # Multi-contract integration tests (IN PROGRESS)
├── Basic.t.sol                # Basic sanity tests (WORKING)
└── README.md                  # This file
```

## Running Tests

### Run All Tests
```bash
forge test
```

### Run Specific Test File
```bash
forge test --match-path test/Basic.t.sol
forge test --match-path test/unit/Treasury.t.sol
```

### Run With Verbosity
```bash
forge test -vv           # Show test names and results
forge test -vvv          # Show execution traces for failing tests
forge test -vvvv         # Show execution traces for all tests
```

### Run Specific Test Function
```bash
forge test --match-test test_Deposit_ETH
```

### Run Gas Report
```bash
forge test --gas-report
```

## Working Tests

### Basic.t.sol ✅
Simple sanity tests to verify test infrastructure:
- Token minting
- Token transfers
- Fuzz testing for token operations

**Status:** 3/3 tests passing

### Treasury.t.sol ✅ (Partial)
Comprehensive tests for the Treasury contract:
- Constructor validation
- ETH and ERC20 deposits
- submitPurchase with ZK proof verification
- transferWithAuthorization
- Edge cases and security tests
- Fuzz testing

**Status:** 13/18 tests passing

#### Passing Tests:
- ✅ Constructor setup
- ✅ ETH deposits
- ✅ ERC20 deposits
- ✅ Invalid proof rejections
- ✅ Expired authorization checks
- ✅ Security validations

#### Tests Needing Fixes:
- ⚠️ test_SubmitPurchase_Success - arithmetic overflow (needs PAYMENT_TOKEN setup)
- ⚠️ test_TransferWithAuthorization_Success - principal token withdrawal issue
- ⚠️ test_SubmitPurchase_Fuzz - small amount handling
- ⚠️ test_MultipleDepositsAndPurchases - balance calculation
- ⚠️ test_TransferWithAuthorization_Expired_After - timestamp arithmetic

## Test Helpers

### BaseTest.sol
Base contract that all tests inherit from, providing:
- Pre-deployed contract instances (Evvm, Staking, Treasury, etc.)
- Test accounts (alice, bob, charlie, admin, etc.)
- Mock tokens (USDC, DAI)
- Common setup and utilities
- Signature helpers

### Mock Contracts

#### MockERC20
Full ERC20 implementation with:
- Minting capabilities
- Burning capabilities
- Configurable decimals

#### MockRiscZeroVerifier
Mock RISC Zero verifier for testing ZK proofs:
- Configurable success/failure
- Individual proof validation
- Integrity checking

## Test Coverage Areas

### Treasury Tests
- ✅ Deposit functionality (ETH & ERC20)
- ✅ ZK proof verification for purchases
- ✅ Authorization-based transfers
- ✅ Error handling and validation
- ✅ Fuzz testing
- ⚠️ Edge cases (partial)

### Planned Coverage (WIP Files)
- Evvm core functionality
- Staking mechanisms
- Username registration and resolution
- P2PSwap order book operations
- Cross-contract integration scenarios
- Multi-user interactions
- Stress testing

## Completing the Test Suite

The following test files are marked as `.wip` (work in progress) and need to be completed:

1. **Evvm.t.sol.wip** - Needs contract interface inspection
2. **Staking.t.sol.wip** - Requires understanding staking mechanics
3. **NameService.t.sol.wip** - Needs actual function names from contract
4. **P2PSwap.t.sol.wip** - Requires order book implementation details
5. **Integration.t.sol.wip** - Depends on completing unit tests

### Steps to Complete:
1. Inspect actual contract interfaces using `cast interface <contract>`
2. Update test files with correct function signatures
3. Remove `.wip` extension once tests compile and pass
4. Add more edge cases and scenarios

## Best Practices

1. **Use BaseTest** - Inherit from BaseTest.sol for consistent setup
2. **Label Tests** - Use descriptive test names: `test_<Action>_<Condition>`
3. **Test Reverts** - Use `vm.expectRevert()` for failure cases
4. **Fuzz Testing** - Add fuzz tests for numerical inputs with `bound()`
5. **Gas Tracking** - Monitor gas usage with `--gas-report`
6. **Comments** - Document complex test scenarios

## Example Test

```solidity
function test_Deposit_ERC20() public {
    uint256 depositAmount = 100 * 10 ** 6; // 100 USDC
    uint256 initialBalance = evvm.getBalance(alice, address(usdc));

    vm.startPrank(alice);
    usdc.approve(address(treasury), depositAmount);
    treasury.deposit(address(usdc), depositAmount);
    vm.stopPrank();

    assertEq(evvm.getBalance(alice, address(usdc)), initialBalance + depositAmount);
}
```

## Debugging Failed Tests

### Common Issues:
1. **Arithmetic Overflow** - Check for underflow in balance calculations
2. **Revert Without Reason** - Use `-vvvv` to see full traces
3. **Gas Limit** - Some complex tests may need gas adjustments
4. **Setup Issues** - Verify BaseTest setup completed successfully

### Debug Commands:
```bash
# Show detailed traces
forge test --match-test <test_name> -vvvv

# Show storage changes
forge test --match-test <test_name> --debug

# Check coverage
forge coverage
```

## Contributing

When adding new tests:
1. Follow existing patterns in BaseTest.sol
2. Group related tests with comments
3. Include both positive and negative test cases
4. Add fuzz tests for numerical inputs
5. Document complex scenarios
6. Ensure tests are deterministic

## Gas Optimization

Tests are designed to help identify gas optimizations:
```bash
forge snapshot              # Create gas snapshot
forge test --gas-report    # View gas usage
```

## Current Status

- ✅ Test infrastructure complete
- ✅ Mock contracts implemented
- ✅ Base test helpers ready
- ✅ Basic tests passing (3/3)
- ✅ Treasury tests mostly passing (13/18)
- ⚠️ Other unit tests need contract interface inspection
- ⚠️ Integration tests pending unit test completion

## Next Steps

1. Fix remaining Treasury test failures
2. Inspect actual contract interfaces for Evvm, Staking, NameService, P2PSwap
3. Update `.wip` test files with correct function signatures
4. Complete integration tests
5. Add more edge cases and security tests
6. Achieve >80% code coverage
