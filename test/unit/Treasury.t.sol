// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {BaseTest} from "../helpers/BaseTest.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {MockRiscZeroVerifier} from "../mocks/MockRiscZeroVerifier.sol";

contract TreasuryTest is BaseTest {
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);

    bytes32 constant EXPECTED_NOTARY_FINGERPRINT = bytes32(uint256(2));
    bytes32 constant EXPECTED_QUERIES_HASH = bytes32(uint256(3));
    string constant EXPECTED_URL = "https://api.etherscan.io/api";

    function setUp() public override {
        super.setUp();

        // Give alice some USDC in Evvm balance
        vm.startPrank(address(treasury));
        evvm.addAmountToUser(alice, address(usdc), 1000 * 10 ** 6);
        vm.stopPrank();

        // Transfer actual USDC to treasury for withdrawals
        vm.prank(alice);
        usdc.transfer(address(treasury), 1000 * 10 ** 6);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(treasury.evvmAddress(), address(evvm));
        assertEq(treasury.EXPECTED_NOTARY_KEY_FINGERPRINT(), EXPECTED_NOTARY_FINGERPRINT);
        assertEq(treasury.EXPECTED_QUERIES_HASH(), EXPECTED_QUERIES_HASH);
        assertEq(treasury.expectedUrlPattern(), EXPECTED_URL);
    }

    // ============ Deposit Tests ============

    function test_Deposit_ETH() public {
        uint256 depositAmount = 1 ether;
        uint256 initialBalance = evvm.getBalance(alice, address(0));

        vm.prank(alice);
        treasury.deposit{value: depositAmount}(address(0), depositAmount);

        assertEq(evvm.getBalance(alice, address(0)), initialBalance + depositAmount);
        assertEq(address(treasury).balance, depositAmount);
    }

    function test_Deposit_ERC20() public {
        uint256 depositAmount = 100 * 10 ** 6; // 100 USDC
        uint256 initialBalance = evvm.getBalance(alice, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        assertEq(evvm.getBalance(alice, address(usdc)), initialBalance + depositAmount);
    }

    function test_Deposit_ETH_InsufficientValue() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.deposit{value: 0.5 ether}(address(0), 1 ether);
    }

    function test_Deposit_Fuzz(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);

        vm.prank(alice);
        treasury.deposit{value: amount}(address(0), amount);

        assertEq(evvm.getBalance(alice, address(0)), amount);
    }

    // ============ submitPurchase Tests ============

    function test_SubmitPurchase_Success() public {
        uint256 purchaseAmount = 100 * 10 ** 6; // 100 USDC

        // Setup: Alice has USDC balance in Evvm
        assertEq(evvm.getBalance(alice, address(usdc)), 1000 * 10 ** 6);

        // Prepare purchase data
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );

        // Mock seal (proof)
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        // Set verifier to succeed
        mockVerifier.setShouldSucceed(true);

        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        // Execute purchase
        vm.prank(merchant);
        treasury.submitPurchase(alice, purchaseAmount, purchaseData, seal);

        // Verify balances changed
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - purchaseAmount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + purchaseAmount);
    }

    function test_SubmitPurchase_InvalidNotaryFingerprint() public {
        bytes memory purchaseData = abi.encode(
            bytes32(uint256(999)), // Wrong fingerprint
            "GET",
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidNotaryKeyFingerprint.selector);
        treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidQueriesHash() public {
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            EXPECTED_URL,
            block.timestamp,
            bytes32(uint256(999)) // Wrong queries hash
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidQueriesHash.selector);
        treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidMethod() public {
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "POST", // Wrong method
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidUrl.selector);
        treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidUrl() public {
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            "https://wrong-url.com", // Wrong URL
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidUrl.selector);
        treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
    }

    function test_SubmitPurchase_ZKProofVerificationFailed() public {
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        // Set verifier to fail
        mockVerifier.setShouldSucceed(false);

        vm.prank(merchant);
        vm.expectRevert(Treasury.ZKProofVerificationFailed.selector);
        treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
    }

    function test_SubmitPurchase_Fuzz(uint256 amount) public {
        amount = bound(amount, 1, 1000 * 10 ** 6); // 0.000001 to 1000 USDC

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(true);

        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));
        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));

        vm.prank(merchant);
        treasury.submitPurchase(alice, amount, purchaseData, seal);

        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - amount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + amount);
    }

    // ============ transferWithAuthorization Tests ============

    function test_TransferWithAuthorization_Success() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce");

        // Ensure alice has enough PAYMENT_TOKEN (USDC) balance in Evvm
        // Note: Alice already has 1000 USDC from setUp, this should be sufficient
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));
        assertGt(aliceBalanceBefore, transferAmount, "Alice doesn't have enough USDC");

        uint256 bobBalanceBefore = evvm.getBalance(bob, address(usdc));

        vm.prank(merchant);
        treasury.transferWithAuthorization(
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            0, // v
            bytes32(0), // r
            bytes32(0)  // s
        );

        // Bob should receive the tokens (withdrawn from alice's Evvm balance)
        assertEq(evvm.getBalance(bob, address(usdc)), bobBalanceBefore + transferAmount);
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - transferAmount);
    }

    function test_TransferWithAuthorization_Expired_Before() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp + 1; // Not yet valid
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce");

        vm.prank(merchant);
        vm.expectRevert(Treasury.Expired.selector);
        treasury.transferWithAuthorization(
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_TransferWithAuthorization_Expired_After() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = 100; // Past timestamp
        uint256 validBefore = 200; // Past timestamp
        bytes32 nonce = keccak256("unique-nonce");

        // Warp to a time after validBefore
        vm.warp(300);

        vm.prank(merchant);
        vm.expectRevert(Treasury.Expired.selector);
        treasury.transferWithAuthorization(
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    // ============ Edge Cases and Security Tests ============

    function test_SubmitPurchase_InsufficientBalance() public {
        uint256 excessiveAmount = 10_000 * 10 ** 6; // More than Alice has

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            EXPECTED_URL,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(true);

        vm.prank(merchant);
        vm.expectRevert();
        treasury.submitPurchase(alice, excessiveAmount, purchaseData, seal);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.deposit(address(0), 0);
    }

    function test_MultipleDepositsAndPurchases() public {
        // Multiple deposits
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            treasury.deposit{value: 1 ether}(address(0), 1 ether);
        }

        assertEq(evvm.getBalance(alice, address(0)), 5 ether);

        // Multiple purchases
        for (uint256 i = 0; i < 3; i++) {
            bytes memory purchaseData = abi.encode(
                EXPECTED_NOTARY_FINGERPRINT,
                "GET",
                EXPECTED_URL,
                block.timestamp,
                EXPECTED_QUERIES_HASH
            );
            bytes memory seal = abi.encodePacked(bytes32(uint256(i)));

            mockVerifier.setShouldSucceed(true);

            vm.prank(merchant);
            treasury.submitPurchase(alice, 100 * 10 ** 6, purchaseData, seal);
        }

        assertEq(evvm.getBalance(alice, address(usdc)), 700 * 10 ** 6); // 1000 - 300
    }
}
