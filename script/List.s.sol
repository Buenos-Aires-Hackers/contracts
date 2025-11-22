// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title List
/// @notice Script to create a listing on the Treasury contract
contract List is Script {
    function run() external {
        // Get Treasury address from environment or use default
        address treasuryAddress = vm.envOr("TREASURY_ADDRESS", address(0));
        require(treasuryAddress != address(0), "TREASURY_ADDRESS not set");

        Treasury treasury = Treasury(treasuryAddress);

        // Get listing parameters from environment variables
        string memory url = vm.envOr("LISTING_URL", string("https://example.com/product"));
        uint256 amount = vm.envUint("LISTING_AMOUNT");
        address shopper = vm.envOr("SHOPPER_ADDRESS", msg.sender);
        
        // Get private credentials (can be computed from raw credentials or provided directly)
        bytes32 privateCredentials = vm.envOr("PRIVATE_CREDENTIALS", bytes32(0));
        
        // If private credentials not provided, compute from raw credentials
        if (privateCredentials == bytes32(0)) {
            string memory fullName = vm.envOr("FULL_NAME", string("John Doe"));
            string memory emailAddress = vm.envOr("EMAIL_ADDRESS", string("john@example.com"));
            string memory homeAddress = vm.envOr("HOME_ADDRESS", string("123 Main St"));
            string memory city = vm.envOr("CITY", string("New York"));
            string memory country = vm.envOr("COUNTRY", string("USA"));
            string memory zip = vm.envOr("ZIP", string("10001"));
            
            Treasury.PrivateCredentialsRaw memory rawCredentials = Treasury.PrivateCredentialsRaw({
                fullName: fullName,
                emailAddress: emailAddress,
                homeAddress: homeAddress,
                city: city,
                country: country,
                zip: zip
            });
            
            privateCredentials = treasury.createPrivateCredentials(rawCredentials);
        }

        // Create listing
        Treasury.Listing memory listing = Treasury.Listing({
            url: url,
            amount: amount,
            shopper: shopper,
            privateCredentials: privateCredentials
        });

        // Calculate listing ID
        bytes32 listingId = treasury.calculateId(listing);
        
        console2.log("Creating listing:");
        console2.log("  URL:", listing.url);
        console2.log("  Amount:", listing.amount);
        console2.log("  Shopper:", listing.shopper);
        console2.log("  Listing ID:", vm.toString(listingId));

        // Get payment token address
        address paymentToken = treasury.PAYMENT_TOKEN();
        
        // Approve payment token if needed (for ERC20)
        if (paymentToken != address(0)) {
            IERC20 token = IERC20(paymentToken);
            uint256 allowance = token.allowance(shopper, address(treasury));
            
            if (allowance < amount) {
                console2.log("Approving payment token...");
                vm.startBroadcast();
                token.approve(address(treasury), amount);
                vm.stopBroadcast();
                console2.log("Approved", amount, "tokens");
            }
        }

        // Create the listing
        vm.startBroadcast();
        treasury.list(listing);
        vm.stopBroadcast();

        console2.log("Listing created successfully!");
        console2.log("Listing ID:", vm.toString(listingId));
    }
}

