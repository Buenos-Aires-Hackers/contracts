// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title Basic Test
 * @notice Simple test to verify the test infrastructure works
 */
contract BasicTest is Test {
    MockERC20 public token;
    address public alice;
    address public bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new MockERC20("Test Token", "TEST", 18);
    }

    function test_TokenMinting() public {
        uint256 amount = 1000 ether;

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
    }

    function test_TokenTransfer() public {
        uint256 amount = 1000 ether;

        token.mint(alice, amount);

        vm.prank(alice);
        token.transfer(bob, 500 ether);

        assertEq(token.balanceOf(alice), 500 ether);
        assertEq(token.balanceOf(bob), 500 ether);
    }

    function test_Fuzz_TokenMinting(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
    }
}
