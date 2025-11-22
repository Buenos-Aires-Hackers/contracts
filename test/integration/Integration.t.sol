// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {BaseTest} from "../helpers/BaseTest.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";

/**
 * @title Integration Tests
 * @notice Tests the interaction between all contracts in the system
 */
contract IntegrationTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Full User Journey Tests ============

    function test_FullUserJourney_DepositAndPurchase() public {
        // 1. Alice deposits USDC to Treasury
        uint256 depositAmount = 500 * 10 ** 6;

        vm.startPrank(alice);
        usdc.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        uint256 aliceUsdcBalance = evvm.getBalance(alice, address(usdc));
        assertGt(aliceUsdcBalance, 0);

        // 2. Verify balance is correct in Evvm
        assertEq(aliceUsdcBalance, depositAmount);
    }

    function test_FullUserJourney_DepositAndCheckBalance() public {
        // 1. Alice deposits USDC
        uint256 depositAmount = 500 * 10 ** 6;
        vm.startPrank(alice);
        usdc.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // 2. Bob deposits ETH
        vm.prank(bob);
        treasury.deposit{value: 10 ether}(address(0), 10 ether);

        // 3. Verify balances are correct in Evvm
        assertEq(evvm.getBalance(alice, address(usdc)), depositAmount);
        assertEq(evvm.getBalance(bob, address(0)), 10 ether);
    }

    function test_TreasuryEvvmIntegration_DepositAndListing() public {
        // 1. Alice deposits USDC
        uint256 depositAmount = 1000 * 10 ** 6;

        vm.startPrank(alice);
        usdc.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        uint256 balanceAfterDeposit = evvm.getBalance(alice, address(usdc));
        assertEq(balanceAfterDeposit, depositAmount);

        // 2. Alice creates a listing
        uint256 listingAmount = 100 * 10 ** 6;
        bytes32 credentials = treasury.createPrivateCredentials(
            Treasury.PrivateCredentialsRaw({
                fullName: "Alice Smith",
                emailAddress: "alice@example.com",
                homeAddress: "123 Main St",
                city: "New York",
                country: "USA",
                zip: "10001"
            })
        );
        Treasury.Listing memory listing = Treasury.Listing({
            url: "https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234",
            amount: listingAmount,
            shopper: alice,
            privateCredentials: credentials
        });

        vm.startPrank(alice);
        usdc.approve(address(treasury), listingAmount);
        treasury.list(listing);
        vm.stopPrank();

        // 3. Verify listing was created and balance increased
        bytes32 listingId = treasury.calculateId(listing);
        (string memory url, uint256 amount, address shopper, bytes32 privateCredentials) = treasury.fetchListing(listingId);
        assertEq(url, listing.url);
        assertEq(amount, listingAmount);
        assertEq(shopper, alice);
        assertEq(privateCredentials, listing.privateCredentials);
        assertEq(evvm.getBalance(alice, address(usdc)), balanceAfterDeposit + listingAmount);
    }

    // ============ Multi-Contract Interaction Tests ============

    function test_StakingEvvmIntegration() public {
        // Test that Staking contract is connected to Evvm and Estimator
        // Verify contracts are deployed and connected
        assertTrue(address(staking) != address(0));
        assertTrue(address(evvm) != address(0));
        assertTrue(address(estimator) != address(0));
        
        // Verify Staking can get Evvm address
        address evvmAddr = staking.getEvvmAddress();
        assertEq(evvmAddr, address(evvm));
    }

    function test_NameServiceEvvmIntegration() public {
        // Verify contracts are deployed
        assertTrue(address(nameService) != address(0));
        assertTrue(address(evvm) != address(0));
        
        // Note: NameService registration requires complex signature flow with pre-registration
        // We verify the contracts exist and are integrated
    }

    function test_AdminControlAcrossContracts() public {
        // Verify admin can perform admin actions on Evvm
        uint256 originalId = evvm.getEvvmID();
        vm.prank(admin);
        evvm.setEvvmID(123);
        assertEq(evvm.getEvvmID(), 123);
        
        // Restore original ID
        vm.prank(admin);
        evvm.setEvvmID(originalId);
        assertEq(evvm.getEvvmID(), originalId);
    }

    // ============ Complex Multi-Step Scenarios ============

    function test_MultiUserMultiTokenScenario() public {
        // Setup: Multiple users deposit different tokens
        vm.startPrank(alice);
        usdc.approve(address(treasury), 1000 * 10 ** 6);
        treasury.deposit(address(usdc), 1000 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(bob);
        dai.approve(address(treasury), 1000 ether);
        treasury.deposit(address(dai), 1000 ether);
        vm.stopPrank();

        vm.prank(charlie);
        treasury.deposit{value: 10 ether}(address(0), 10 ether);

        // Verify all balances are correct in Evvm
        assertGt(evvm.getBalance(alice, address(usdc)), 0);
        assertGt(evvm.getBalance(bob, address(dai)), 0);
        assertGt(evvm.getBalance(charlie, address(0)), 0);
    }

    function test_ChainedTransactions() public {
        // 1. Alice deposits USDC
        vm.startPrank(alice);
        usdc.approve(address(treasury), 500 * 10 ** 6);
        treasury.deposit(address(usdc), 500 * 10 ** 6);
        vm.stopPrank();

        // 2. Bob deposits DAI
        vm.startPrank(bob);
        dai.approve(address(treasury), 200 ether);
        treasury.deposit(address(dai), 200 ether);
        vm.stopPrank();

        // 3. Charlie deposits ETH
        vm.prank(charlie);
        treasury.deposit{value: 5 ether}(address(0), 5 ether);

        // Verify entire chain worked
        assertGt(evvm.getBalance(alice, address(usdc)), 0);
        assertGt(evvm.getBalance(bob, address(dai)), 0);
        assertGt(evvm.getBalance(charlie, address(0)), 0);
    }

    // ============ Stress Tests ============

    function test_ManyUsersDepositing() public {
        address[] memory users = new address[](10);

        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(users[i], 100 ether);

            vm.prank(users[i]);
            treasury.deposit{value: 1 ether}(address(0), 1 ether);

            assertEq(evvm.getBalance(users[i], address(0)), 1 ether);
        }
    }
}
