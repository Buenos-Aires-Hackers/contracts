// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {BaseTest} from "../helpers/BaseTest.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {MockRiscZeroVerifier} from "../mocks/MockRiscZeroVerifier.sol";
import {ErrorsLib} from "@evvm/testnet-contracts/contracts/treasury/lib/ErrorsLib.sol";

contract TreasuryTest is BaseTest {
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event ListingCreated(Treasury.Listing listing, bytes32 id);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    bytes32 constant EXPECTED_NOTARY_FINGERPRINT = bytes32(uint256(2));
    bytes32 constant EXPECTED_QUERIES_HASH = bytes32(uint256(3));

    function setUp() public override {
        super.setUp();

        // Give alice some USDC in Evvm balance
        vm.startPrank(address(treasury));
        evvm.addAmountToUser(alice, address(usdc), 1000 * 10 ** 6);
        vm.stopPrank();

        // Give alice actual USDC for creating listings
        usdc.mint(alice, 1000 * 10 ** 6);

        // Transfer some USDC to treasury for withdrawals
        vm.prank(alice);
        usdc.transfer(address(treasury), 500 * 10 ** 6);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(treasury.evvmAddress(), address(evvm));
        assertEq(treasury.EXPECTED_NOTARY_KEY_FINGERPRINT(), EXPECTED_NOTARY_FINGERPRINT);
        assertEq(treasury.EXPECTED_QUERIES_HASH(), EXPECTED_QUERIES_HASH);
        assertEq(treasury.PAYMENT_TOKEN(), address(usdc));
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

    function test_DepositFrom() public {
        uint256 depositAmount = 100 * 10 ** 6;

        // Alice approves treasury to spend her tokens, then deposits for Bob
        vm.startPrank(alice);
        usdc.approve(address(treasury), depositAmount);
        vm.stopPrank();

        // Alice calls depositFrom to deposit her tokens for Bob
        vm.prank(alice);
        treasury.depositFrom(alice, address(usdc), depositAmount);

        // Bob should have the balance in Evvm (deposited on his behalf)
        assertEq(evvm.getBalance(alice, address(usdc)), 1000 * 10 ** 6 + depositAmount);
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

    // ============ Listing Tests ============

    function test_CreateListing() public {
        uint256 listingAmount = 100 * 10 ** 6;
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234",
            amount: listingAmount,
            shopper: alice
        });

        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        // Verify alice's USDC was deposited
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore + listingAmount);

        // Verify listing was stored
        bytes32 listingId = treasury.calculateId(listing);
        (string memory url, uint256 amount, address shopper) = treasury.fetchListing(listingId);
        assertEq(url, listing.url);
        assertEq(amount, listing.amount);
        assertEq(shopper, listing.shopper);
    }

    function test_CalculateId() public {
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-2222222-3333333",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        bytes32 expectedId = keccak256(abi.encode(listing));
        bytes32 actualId = treasury.calculateId(listing);

        assertEq(actualId, expectedId);
    }

    // ============ submitPurchase Tests ============

    function test_SubmitPurchase_Success() public {
        // Step 1: Create a listing
        uint256 listingAmount = 100 * 10 ** 6;
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-2345678-9012345",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        // Step 2: Prepare purchase data
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(true);

        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        // Step 3: Submit purchase
        vm.prank(merchant);
        treasury.submitPurchase(listingId, purchaseData, seal);

        // Verify balances changed
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - listingAmount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + listingAmount);

        // Verify listing was deleted
        (, , address shopper) = treasury.fetchListing(listingId);
        assertEq(shopper, address(0));
    }

    function test_SubmitPurchase_InvalidListing() public {
        bytes32 nonExistentId = bytes32(uint256(999));

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            "https://www.amazon.com/gp/your-account/order-details/?orderID=111-3456789-0123456",
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidListing.selector);
        treasury.submitPurchase(nonExistentId, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidNotaryFingerprint() public {
        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-4567890-1234567",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listing.amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            bytes32(uint256(999)), // Wrong fingerprint
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidNotaryKeyFingerprint.selector);
        treasury.submitPurchase(listingId, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidQueriesHash() public {
        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-5678901-2345678",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listing.amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            bytes32(uint256(999)) // Wrong queries hash
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidQueriesHash.selector);
        treasury.submitPurchase(listingId, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidMethod() public {
        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-6789012-3456789",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listing.amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "POST", // Wrong method
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidUrl.selector);
        treasury.submitPurchase(listingId, purchaseData, seal);
    }

    function test_SubmitPurchase_InvalidUrl() public {
        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-7890123-4567890",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listing.amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            "https://www.amazon.com/gp/your-account/order-details/?orderID=999-9999999-9999999", // Wrong order ID
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidUrl.selector);
        treasury.submitPurchase(listingId, purchaseData, seal);
    }

    function test_SubmitPurchase_ZKProofVerificationFailed() public {
        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-8901234-5678901",
            amount: 100 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listing.amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(false);

        vm.prank(merchant);
        vm.expectRevert(Treasury.ZKProofVerificationFailed.selector);
        treasury.submitPurchase(listingId, purchaseData, seal);
    }

    // ============ transferWithAuthorization Tests ============
    // NOTE: This is a CUSTOM implementation using ERC-3009 signature for x402 compatibility
    // It's NOT standard ERC-3009 - it withdraws from recipient's evvm balance, not sender's

    function test_FullMarketplaceFlow() public {
        // Complete flow: Alice lists → Bob proves purchase → Bob gets paid via x402

        uint256 listingAmount = 100 * 10 ** 6;

        // Step 1: Alice creates listing for Amazon shoes
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1111111-1111111",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        // Alice has evvm balance, Bob has none yet
        assertEq(evvm.getBalance(alice, address(usdc)), 1000 * 10 ** 6 + listingAmount);
        assertEq(evvm.getBalance(bob, address(usdc)), 0);

        // Step 2-4: Bob buys with credit card, gets receipt, webapp creates ZK proof,
        // Bob submits proof → Alice's evvm balance transfers to Bob's evvm balance
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));
        mockVerifier.setShouldSucceed(true);

        vm.prank(bob);
        treasury.submitPurchase(listingId, purchaseData, seal);

        // Now Bob has evvm balance, Alice's decreased
        assertEq(evvm.getBalance(alice, address(usdc)), 1000 * 10 ** 6);
        assertEq(evvm.getBalance(bob, address(usdc)), listingAmount);

        // Step 5: Webapp backend automatically triggers x402 payout
        // Backend signs authorization for Bob to withdraw his earned payment
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("payment-release-1");

        // Transfer real USDC to treasury so it can process withdrawal
        vm.prank(alice);
        usdc.transfer(address(treasury), listingAmount);

        uint256 bobWalletBefore = usdc.balanceOf(bob);

        // Backend signs the payment release (automated after ZK proof verification)
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            bob,
            listingAmount,
            validAfter,
            validBefore,
            nonce
        );

        // x402 facilitator submits the backend-signed authorization
        treasury.transferWithAuthorization(
            backend,
            bob,
            listingAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        // Bob's evvm balance withdrawn, wallet balance increased
        assertEq(evvm.getBalance(bob, address(usdc)), 0);
        assertEq(usdc.balanceOf(bob), bobWalletBefore + listingAmount);
    }

    function test_TransferWithAuthorization_Success() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-1");

        // Give Bob some evvm USDC balance (simulating he got paid via submitPurchase)
        vm.prank(address(treasury));
        evvm.addAmountToUser(bob, address(usdc), transferAmount);

        // Transfer USDC to treasury so it can process the withdrawal
        vm.prank(alice);
        usdc.transfer(address(treasury), transferAmount);

        uint256 bobEvvmBalanceBefore = evvm.getBalance(bob, address(usdc));
        uint256 bobWalletBalanceBefore = usdc.balanceOf(bob);

        // Backend signs the authorization for Bob to withdraw
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        // Expect ERC-3009 AuthorizationUsed event
        vm.expectEmit(true, true, false, false);
        emit Treasury.AuthorizationUsed(backend, nonce);

        // x402 submits the backend-signed authorization
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        // Bob's evvm balance should decrease
        assertEq(evvm.getBalance(bob, address(usdc)), bobEvvmBalanceBefore - transferAmount);
        // Bob's wallet balance should increase
        assertEq(usdc.balanceOf(bob), bobWalletBalanceBefore + transferAmount);
    }

    function test_TransferWithAuthorization_InvalidSignature() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-2");

        // Alice signs instead of backend (wrong signer)
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            alicePrivateKey,
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        vm.expectRevert(Treasury.InvalidSignature.selector);
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function test_TransferWithAuthorization_ReplayProtection() public {
        uint256 transferAmount = 50 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-3");

        // Give Bob evvm USDC balance
        vm.prank(address(treasury));
        evvm.addAmountToUser(bob, address(usdc), transferAmount * 2);

        // Transfer USDC to treasury
        vm.prank(alice);
        usdc.transfer(address(treasury), transferAmount * 2);

        // Backend signs the authorization
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        // First call succeeds
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        // Second call with same signature should fail (nonce already used)
        vm.expectRevert(Treasury.AuthorizationAlreadyUsed.selector);
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function test_TransferWithAuthorization_Expired_Before() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp + 1; // Not yet valid
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-4");

        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        vm.expectRevert(Treasury.Expired.selector);
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function test_TransferWithAuthorization_Expired_After() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = 100;
        uint256 validBefore = 200;
        bytes32 nonce = keccak256("unique-nonce-5");

        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        vm.warp(300);

        vm.expectRevert(Treasury.Expired.selector);
        treasury.transferWithAuthorization(
            backend,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    // ============ Locking Mechanism Tests ============

    function test_LockedFunds_CannotWithdrawWhileListingActive() public {
        uint256 listingAmount = 200 * 10 ** 6;

        // Alice has 1500 USDC in evvm (1000 from setup + 500 from deposit in setUp)
        uint256 aliceInitialBalance = evvm.getBalance(alice, address(usdc));

        // Alice creates a listing, locking 200 USDC
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1111111-1111111",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        // Transfer USDC to treasury for withdrawal attempts
        vm.prank(alice);
        usdc.transfer(address(treasury), aliceInitialBalance);

        // Try to withdraw more than unlocked amount - should fail
        // Alice has (aliceInitialBalance + listingAmount) total, but listingAmount is locked
        uint256 tryToWithdraw = aliceInitialBalance + 1; // More than unlocked

        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-locked")
        );

        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        treasury.transferWithAuthorization(
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-locked"),
            v,
            r,
            s
        );
    }

    function test_LockedFunds_UnlockedAfterPurchaseComplete() public {
        uint256 listingAmount = 100 * 10 ** 6;

        // Alice creates listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-2222222-2222222",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        // Funds are locked, Alice has (initial - listingAmount) available
        uint256 aliceBalance = evvm.getBalance(alice, address(usdc));

        // Bob completes the purchase
        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));
        mockVerifier.setShouldSucceed(true);

        vm.prank(bob);
        treasury.submitPurchase(listingId, purchaseData, seal);

        // After purchase, Alice's locked amount should be 0
        // Alice's remaining balance should be withdrawable
        uint256 aliceRemainingBalance = evvm.getBalance(alice, address(usdc));

        if (aliceRemainingBalance > 0) {
            vm.prank(address(treasury));
            evvm.addAmountToUser(charlie, address(usdc), aliceRemainingBalance);

            vm.prank(alice);
            usdc.transfer(address(treasury), aliceRemainingBalance);

            (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
                backendPrivateKey,
                backend,
                charlie,
                aliceRemainingBalance,
                block.timestamp - 1,
                block.timestamp + 1 hours,
                keccak256("withdraw-after-unlock")
            );

            // Should succeed because funds are no longer locked
            treasury.transferWithAuthorization(
                backend,
                charlie,
                aliceRemainingBalance,
                block.timestamp - 1,
                block.timestamp + 1 hours,
                keccak256("withdraw-after-unlock"),
                v,
                r,
                s
            );

            assertEq(evvm.getBalance(charlie, address(usdc)), 0);
        }
    }

    function test_LockedFunds_MultipleListings() public {
        uint256 listing1Amount = 100 * 10 ** 6;
        uint256 listing2Amount = 150 * 10 ** 6;
        uint256 totalLocked = listing1Amount + listing2Amount;

        Treasury.Listing memory listing1 = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-3333333-3333333",
            amount: listing1Amount,
            shopper: alice
        });

        Treasury.Listing memory listing2 = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-4444444-4444444",
            amount: listing2Amount,
            shopper: alice
        });

        uint256 aliceInitialBalance = evvm.getBalance(alice, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(treasury), totalLocked);
        treasury.list(listing1);
        treasury.list(listing2);
        vm.stopPrank();

        // Alice has totalLocked locked, transfer funds to treasury for withdrawal test
        vm.prank(alice);
        usdc.transfer(address(treasury), aliceInitialBalance + totalLocked);

        // Try to withdraw more than unlocked amount - should fail
        uint256 tryToWithdraw = aliceInitialBalance + 1; // More than unlocked

        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-too-much")
        );

        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        treasury.transferWithAuthorization(
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-too-much"),
            v,
            r,
            s
        );

        // Complete first listing
        bytes32 listing1Id = treasury.calculateId(listing1);
        bytes memory purchaseData1 = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing1.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal1 = abi.encodePacked(bytes32(uint256(1)));
        mockVerifier.setShouldSucceed(true);

        vm.prank(bob);
        treasury.submitPurchase(listing1Id, purchaseData1, seal1);

        // After completing first listing, Alice has listing2Amount locked
        // She can now withdraw up to (aliceInitialBalance + listing1Amount - Bob's balance)
        // But Bob got the listing1Amount, so Alice can withdraw aliceInitialBalance
    }

    function test_LockedFunds_ExactlyLockedAmount() public {
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        // Alice locks all her current funds
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-5555555-5555555",
            amount: aliceBalanceBefore,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), aliceBalanceBefore);
        treasury.list(listing);
        vm.stopPrank();

        // After listing, Alice has (aliceBalanceBefore + aliceBalanceBefore) total, with aliceBalanceBefore locked
        // So she has aliceBalanceBefore unlocked
        uint256 aliceBalanceAfter = evvm.getBalance(alice, address(usdc));
        assertEq(aliceBalanceAfter, aliceBalanceBefore * 2); // Initial + deposited amount

        // Transfer funds to treasury for withdrawal attempt
        vm.prank(alice);
        usdc.transfer(address(treasury), aliceBalanceAfter);

        // Try to withdraw more than unlocked - should fail
        uint256 tryToWithdraw = aliceBalanceBefore + 1; // More than unlocked amount

        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            backendPrivateKey,
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-when-half-locked")
        );

        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        treasury.transferWithAuthorization(
            backend,
            alice,
            tryToWithdraw,
            block.timestamp - 1,
            block.timestamp + 1 hours,
            keccak256("try-withdraw-when-half-locked"),
            v,
            r,
            s
        );
    }

    // ============ Amazon URL Format Tests ============

    function test_AmazonOrderDetailsUrlFormat() public {
        uint256 listingAmount = 100 * 10 ** 6;
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(true);

        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        vm.prank(merchant);
        treasury.submitPurchase(listingId, purchaseData, seal);

        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - listingAmount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + listingAmount);
    }

    function test_AmazonPrintUrlFormat() public {
        uint256 listingAmount = 100 * 10 ** 6;
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/css/summary/print.html?orderID=111-9876543-2109876",
            amount: listingAmount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);

        bytes memory purchaseData = abi.encode(
            EXPECTED_NOTARY_FINGERPRINT,
            "GET",
            listing.url,
            block.timestamp,
            EXPECTED_QUERIES_HASH
        );
        bytes memory seal = abi.encodePacked(bytes32(uint256(1)));

        mockVerifier.setShouldSucceed(true);

        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        vm.prank(merchant);
        treasury.submitPurchase(listingId, purchaseData, seal);

        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - listingAmount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + listingAmount);
    }

    // ============ Multiple Listings Tests ============

    function test_MultipleListings() public {
        Treasury.Listing memory listing1 = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-9012345-6789012",
            amount: 50 * 10 ** 6,
            shopper: alice
        });

        Treasury.Listing memory listing2 = Treasury.Listing({
            url: "https://www.amazon.com/gp/css/summary/print.html?orderID=111-0123456-7890123",
            amount: 75 * 10 ** 6,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), 125 * 10 ** 6);
        treasury.list(listing1);
        treasury.list(listing2);
        vm.stopPrank();

        bytes32 id1 = treasury.calculateId(listing1);
        bytes32 id2 = treasury.calculateId(listing2);

        // Verify both listings exist
        (, uint256 amount1, address shopper1) = treasury.fetchListing(id1);
        (, uint256 amount2, address shopper2) = treasury.fetchListing(id2);

        assertEq(amount1, listing1.amount);
        assertEq(shopper1, alice);
        assertEq(amount2, listing2.amount);
        assertEq(shopper2, alice);
    }

    function test_Fuzz_Listing(uint256 amount) public {
        amount = bound(amount, 1, 500 * 10 ** 6);

        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1111111-1111111",
            amount: amount,
            shopper: alice
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), amount);
        treasury.list(listing);
        vm.stopPrank();

        bytes32 listingId = treasury.calculateId(listing);
        (, uint256 storedAmount, address storedShopper) = treasury.fetchListing(listingId);

        assertEq(storedAmount, amount);
        assertEq(storedShopper, alice);
    }
}
