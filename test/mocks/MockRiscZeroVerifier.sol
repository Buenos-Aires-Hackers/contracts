// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IRiscZeroVerifier, Receipt} from "@risc0/contracts/IRiscZeroVerifier.sol";

contract MockRiscZeroVerifier is IRiscZeroVerifier {
    bool public shouldSucceed = true;
    mapping(bytes32 => bool) public validProofs;

    function setShouldSucceed(bool _shouldSucceed) external {
        shouldSucceed = _shouldSucceed;
    }

    function setValidProof(bytes32 proofHash, bool valid) external {
        validProofs[proofHash] = valid;
    }

    function verify(bytes calldata seal, bytes32 imageId, bytes32 journalHash) external view {
        bytes32 proofHash = keccak256(abi.encodePacked(seal, imageId, journalHash));

        if (!shouldSucceed && !validProofs[proofHash]) {
            revert("MockRiscZeroVerifier: verification failed");
        }
    }

    function verifyIntegrity(Receipt calldata) external view {
        if (!shouldSucceed) {
            revert("MockRiscZeroVerifier: integrity check failed");
        }
    }
}
