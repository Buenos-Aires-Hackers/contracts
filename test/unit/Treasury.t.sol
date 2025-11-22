// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {BaseTest} from "../helpers/BaseTest.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {MockRiscZeroVerifier} from "../mocks/MockRiscZeroVerifier.sol";

contract TreasuryTest is BaseTest {
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event ListingCreated(Treasury.Listing listing, bytes32 id);

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

    function test_TransferWithAuthorization_Success() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-1");

        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));
        assertGt(aliceBalanceBefore, transferAmount, "Alice doesn't have enough USDC");

        uint256 bobBalanceBefore = evvm.getBalance(bob, address(usdc));

        // Alice signs the authorization
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            alicePrivateKey,
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        // Merchant submits the signed authorization
        vm.prank(merchant);
        treasury.transferWithAuthorization(
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        assertEq(evvm.getBalance(bob, address(usdc)), bobBalanceBefore + transferAmount);
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - transferAmount);
    }

    function test_TransferWithAuthorization_InvalidSignature() public {
        uint256 transferAmount = 100 * 10 ** 6;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("unique-nonce-2");

        // Bob signs instead of Alice (wrong signer)
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            bobPrivateKey,
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        vm.prank(merchant);
        vm.expectRevert(Treasury.InvalidSignature.selector);
        treasury.transferWithAuthorization(
            alice,
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

        // Alice signs the authorization
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            alicePrivateKey,
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        // First call succeeds
        vm.prank(merchant);
        treasury.transferWithAuthorization(
            alice,
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
        vm.prank(merchant);
        vm.expectRevert(Treasury.AuthorizationAlreadyUsed.selector);
        treasury.transferWithAuthorization(
            alice,
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
            alicePrivateKey,
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

        vm.prank(merchant);
        vm.expectRevert(Treasury.Expired.selector);
        treasury.transferWithAuthorization(
            alice,
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
            alicePrivateKey,
            alice,
            bob,
            transferAmount,
            validAfter,
            validBefore,
            nonce
        );

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
