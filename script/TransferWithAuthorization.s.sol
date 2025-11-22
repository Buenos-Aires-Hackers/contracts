// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";

/// @title TransferWithAuthorization
/// @notice Script to execute a transfer with authorization (ERC-3009 style)
contract TransferWithAuthorization is Script {
    function run() external {
        // Get Treasury address from environment
        address treasuryAddress = vm.envOr("TREASURY_ADDRESS", address(0));
        require(treasuryAddress != address(0), "TREASURY_ADDRESS not set");

        Treasury treasury = Treasury(treasuryAddress);

        // Get transfer parameters
        address from = vm.envAddress("FROM_ADDRESS");
        address to = vm.envAddress("TO_ADDRESS");
        uint256 value = vm.envUint("TRANSFER_VALUE");
        
        // Get validity window (defaults to 1 hour window)
        uint256 validAfter = vm.envOr("VALID_AFTER", block.timestamp - 1);
        uint256 validBefore = vm.envOr("VALID_BEFORE", block.timestamp + 1 hours);
        
        // Get nonce (must be unique)
        bytes32 nonce = vm.envBytes32("NONCE");
        require(nonce != bytes32(0), "NONCE not set");

        // Get private key for signing (from environment or use default)
        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        require(privateKey != 0, "PRIVATE_KEY not set");

        // Verify the private key matches the 'from' address
        address signerAddress = vm.addr(privateKey);
        require(signerAddress == from, "Private key does not match FROM_ADDRESS");

        console2.log("Preparing transfer with authorization:");
        console2.log("  From:", from);
        console2.log("  To:", to);
        console2.log("  Value:", value);
        console2.log("  Valid After:", validAfter);
        console2.log("  Valid Before:", validBefore);
        console2.log("  Nonce:");
        console2.logBytes32(nonce);

        // Sign the authorization
        (uint8 v, bytes32 r, bytes32 s) = signTransferAuthorization(
            treasury,
            privateKey,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );

        console2.log("Signature generated");

        // Execute the transfer
        vm.startBroadcast();
        treasury.transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
        vm.stopBroadcast();

        console2.log("Transfer with authorization executed successfully!");
    }

    /// @notice Sign a transfer authorization message (EIP-712)
    /// @param treasury Treasury contract instance
    /// @param privateKey Private key of the signer
    /// @param from Authorizer address
    /// @param to Recipient address
    /// @param value Transfer amount
    /// @param validAfter Timestamp after which authorization is valid
    /// @param validBefore Timestamp before which authorization is valid
    /// @param nonce Unique nonce
    /// @return v Signature component
    /// @return r Signature component
    /// @return s Signature component
    function signTransferAuthorization(
        Treasury treasury,
        uint256 privateKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
            "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = treasury.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);
    }
}

