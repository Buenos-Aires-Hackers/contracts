// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";

/// @title SubmitPurchase
/// @notice Script to submit a purchase with ZK proof verification
contract SubmitPurchase is Script {
    function run() external {
        // Get Treasury address from environment
        address treasuryAddress = vm.envOr("TREASURY_ADDRESS", address(0));
        require(treasuryAddress != address(0), "TREASURY_ADDRESS not set");

        Treasury treasury = Treasury(treasuryAddress);

        // Get listing ID
        bytes32 listingId = vm.envBytes32("LISTING_ID");
        require(listingId != bytes32(0), "LISTING_ID not set");

        // Get purchase data parameters
        bytes32 notaryKeyFingerprint = vm.envBytes32("NOTARY_KEY_FINGERPRINT");
        string memory method = vm.envOr("HTTP_METHOD", string("GET"));
        string memory url = vm.envOr("PURCHASE_URL", string(""));
        require(bytes(url).length > 0, "PURCHASE_URL not set");
        bytes32 queriesHash = vm.envBytes32("QUERIES_HASH");
        bytes32 privateCredentials = vm.envBytes32("PRIVATE_CREDENTIALS");

        // Get ZK proof seal
        bytes memory seal = vm.envBytes("ZK_PROOF_SEAL");
        require(seal.length > 0, "ZK_PROOF_SEAL not set");

        // Encode purchase data
        bytes memory purchaseData = abi.encode(notaryKeyFingerprint, method, url, queriesHash, privateCredentials);

        console2.log("Submitting purchase:");
        console2.log("  Listing ID:", vm.toString(listingId));
        console2.log("  Notary Key Fingerprint:");
        console2.logBytes32(notaryKeyFingerprint);
        console2.log("  Method:", method);
        console2.log("  URL:", url);
        console2.log("  Queries Hash:");
        console2.logBytes32(queriesHash);
        console2.log("  Seal length:", seal.length);

        // Submit the purchase
        vm.startBroadcast();
        treasury.submitPurchase(listingId, purchaseData, seal);
        vm.stopBroadcast();

        console2.log("Purchase submitted successfully!");
    }
}
