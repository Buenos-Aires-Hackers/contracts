// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {RiscZeroCheats} from "@risc0/contracts/test/RiscZeroCheats.sol";
import {IRiscZeroVerifier} from "@risc0/contracts/IRiscZeroVerifier.sol";
import {NetworkConfig} from "../../script/NetworkConfig.sol";

/**
 * @title RiscZeroTestHelper
 * @notice Helper contract for testing with RISC Zero proofs
 * @dev Extends RiscZeroCheats to provide proof generation capabilities
 *
 * Usage:
 * 1. For tests that need real proofs, extend this contract instead of BaseTest
 * 2. Call prove() with your ELF path and input to generate a real proof
 * 3. Use the returned journal and seal in your tests
 *
 * Example:
 * ```solidity
 * contract MyTest is RiscZeroTestHelper {
 *     function testWithRealProof() public {
 *         bytes memory input = abi.encode(...);
 *         (bytes memory journal, bytes memory seal) = prove("path/to/your/program.elf", input);
 *
 *         // Use seal in your test
 *         treasury.submitPurchase(listingId, purchaseData, seal);
 *     }
 * }
 * ```
 *
 * Note: This requires:
 * - Rust toolchain installed
 * - RISC Zero dependencies in lib/risc0-ethereum
 * - Your zkVM program compiled to ELF format
 */
abstract contract RiscZeroTestHelper is Test, RiscZeroCheats {
    /// @notice Get the RISC Zero verifier from Base Sepolia
    /// @dev Returns the verifier router deployed on Base Sepolia
    function getRiscZeroVerifier() internal pure returns (IRiscZeroVerifier) {
        return NetworkConfig.getRiscZeroVerifier();
    }

    /// @notice Generate a proof for the given ELF path and input
    /// @param elfPath Path to the compiled ELF file of your zkVM program
    /// @param input Input data for your zkVM program (will be ABI encoded)
    /// @return journal The journal output from the zkVM execution
    /// @return seal The proof seal that can be verified on-chain
    /// @dev This calls the RISC Zero prover via FFI to generate a real proof
    ///      Make sure your ELF path is relative to the project root
    function generateProof(string memory elfPath, bytes memory input)
        internal
        returns (bytes memory journal, bytes memory seal)
    {
        return prove(elfPath, input);
    }

    /// @notice Generate a proof and return the journal hash
    /// @param elfPath Path to the compiled ELF file
    /// @param input Input data for the zkVM program
    /// @return journal The journal output
    /// @return seal The proof seal
    /// @return journalHash The SHA256 hash of the journal (used in verify calls)
    function generateProofWithHash(string memory elfPath, bytes memory input)
        internal
        returns (bytes memory journal, bytes memory seal, bytes32 journalHash)
    {
        (journal, seal) = generateProof(elfPath, input);
        journalHash = sha256(journal);
        return (journal, seal, journalHash);
    }

    /// @notice Verify a proof using the Base Sepolia verifier
    /// @param seal The proof seal
    /// @param imageId The image ID of your zkVM program
    /// @param journalHash The SHA256 hash of the journal
    /// @dev This will revert if verification fails
    function verifyProof(bytes memory seal, bytes32 imageId, bytes32 journalHash) internal view {
        getRiscZeroVerifier().verify(seal, imageId, journalHash);
    }
}
