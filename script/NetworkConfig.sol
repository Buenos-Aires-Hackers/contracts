// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IRiscZeroVerifier} from "@risc0/contracts/IRiscZeroVerifier.sol";

/**
 * @title NetworkConfig
 * @notice Configuration for Base Sepolia network with RISC Zero verifier addresses
 */
library NetworkConfig {
    /// @notice Base Sepolia chain ID
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @notice RISC Zero Verifier Router address on Base Sepolia
    /// @dev This is the recommended verifier to use as it routes to appropriate verifiers
    ///      based on the proof version. See: https://dev.risczero.com/api/blockchain-integration/contracts/verifier
    address public constant RISC_ZERO_VERIFIER_ROUTER = 0x02E1F6e057832F9EA0C6c078B8aBd0E81E9FD2d1;

    /// @notice Base Sepolia RPC URL for forking
    string public constant BASE_SEPOLIA_RPC_URL = "https://sepolia.base.org";

    /**
     * @notice Get the RISC Zero verifier for Base Sepolia
     * @return The IRiscZeroVerifier interface for the router
     */
    function getRiscZeroVerifier() internal pure returns (IRiscZeroVerifier) {
        return IRiscZeroVerifier(RISC_ZERO_VERIFIER_ROUTER);
    }

    /**
     * @notice Check if the current chain is Base Sepolia
     * @param chainId The chain ID to check
     * @return True if the chain ID matches Base Sepolia
     */
    function isBaseSepolia(uint256 chainId) internal pure returns (bool) {
        return chainId == BASE_SEPOLIA_CHAIN_ID;
    }
}
