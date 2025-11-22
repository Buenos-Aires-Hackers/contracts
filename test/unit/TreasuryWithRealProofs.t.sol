// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

/**
 * @title TreasuryWithRealProofs
 * @notice Tests Treasury with real RISC Zero proofs
 * @dev These tests will be skipped if the zkVM program is not compiled
 * 
 * To enable these tests:
 * 1. Compile your zkVM program to ELF format
 * 2. Update ELF_PATH to point to your compiled program
 * 3. Update YOUR_IMAGE_ID with your program's image ID
 * 4. Update RISC Zero constants in BaseTest to match your program
 */

import {BaseTest} from "../helpers/BaseTest.sol";
import {RiscZeroTestHelper} from "../helpers/RiscZeroTestHelper.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {NetworkConfig} from "../../script/NetworkConfig.sol";

contract TreasuryWithRealProofs is BaseTest, RiscZeroTestHelper {
    // Path to your compiled zkVM program ELF file
    // This should be relative to the project root
    string constant ELF_PATH = "target/riscv32im-risc0-zkvm-elf/release/your_program";
    
    // Your zkVM program's image ID (obtained after compiling)
    bytes32 constant YOUR_IMAGE_ID = BaseTest.RISC0_IMAGE_ID;

    /// @notice Verify we're forking Base Sepolia and using the real verifier
    function test_VerifyForkAndVerifier() public {
        // Verify we're on Base Sepolia fork
        require(
            NetworkConfig.isBaseSepolia(block.chainid),
            "Must be forking Base Sepolia"
        );
        assertEq(block.chainid, NetworkConfig.BASE_SEPOLIA_CHAIN_ID);
        
        // Verify we're using the real verifier router
        assertEq(
            address(treasury.VERIFIER()),
            NetworkConfig.RISC_ZERO_VERIFIER_ROUTER,
            "Must use real RISC Zero verifier router"
        );
    }

    function test_SubmitPurchase_WithRealProof() public {
        // Skip if ELF doesn't exist
        if (!vm.isFile(ELF_PATH)) {
            vm.skip(true);
            return;
        }
        // Step 1: Create a listing
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

        // Step 2: Generate a real ZK proof for the purchase
        // Your zkVM program should verify the Amazon purchase and extract relevant data
        // NOTE: Update this to match your zkVM program's expected input format
        bytes memory purchaseInput = abi.encode(listing.url);
        
        // Generate proof using RISC Zero FFI
        (bytes memory journal, bytes memory seal, bytes32 journalHash) = 
            generateProofWithHash(ELF_PATH, purchaseInput);
        
        // Verify proof was generated
        require(seal.length > 0, "Proof generation failed - seal is empty");
        require(journal.length > 0, "Proof generation failed - journal is empty");

        // Step 3: Decode the journal to get the purchase data
        // The journal format should match what your zkVM program outputs
        // NOTE: Update this to match your zkVM program's output format
        // Treasury expects: (bytes32 notaryKeyFingerprint, string method, string url, bytes32 queriesHash)
        (
            bytes32 notaryKeyFingerprint,
            string memory method,
            string memory url,
            bytes32 queriesHash
        ) = abi.decode(journal, (bytes32, string, string, bytes32));

        // Step 4: Prepare purchase data (must match Treasury's expected format)
        bytes memory purchaseData = abi.encode(
            notaryKeyFingerprint,
            method,
            url,
            queriesHash
        );

        // Verify the journal hash matches what we'll pass to verify()
        bytes32 expectedJournalHash = sha256(purchaseData);
        assertEq(expectedJournalHash, journalHash, "Journal hash mismatch");
        
        // Verify the image ID matches
        assertEq(treasury.IMAGE_ID(), YOUR_IMAGE_ID, "Image ID mismatch");
        
        // Verify notary fingerprint and queries hash match Treasury expectations
        assertEq(
            notaryKeyFingerprint,
            treasury.EXPECTED_NOTARY_KEY_FINGERPRINT(),
            "Notary fingerprint mismatch"
        );
        assertEq(
            queriesHash,
            treasury.EXPECTED_QUERIES_HASH(),
            "Queries hash mismatch"
        );

        // Step 5: Submit the purchase with real proof
        uint256 merchantBalanceBefore = evvm.getBalance(merchant, address(usdc));
        uint256 aliceBalanceBefore = evvm.getBalance(alice, address(usdc));

        vm.prank(merchant);
        treasury.submitPurchase(listingId, purchaseData, seal);

        // Step 6: Verify balances changed
        assertEq(evvm.getBalance(alice, address(usdc)), aliceBalanceBefore - listingAmount);
        assertEq(evvm.getBalance(merchant, address(usdc)), merchantBalanceBefore + listingAmount);

        // Verify listing was deleted
        (, , address shopper) = treasury.fetchListing(listingId);
        assertEq(shopper, address(0));
    }

    /**
     * @notice Helper function to generate a proof for a purchase
     * @dev This should match your zkVM program's expected input format
     */
    function generatePurchaseProof(
        string memory amazonUrl
    ) internal returns (bytes memory purchaseData, bytes memory seal) {
        // Prepare input for your zkVM program
        // NOTE: Update this to match your zkVM program's expected input
        bytes memory input = abi.encode(amazonUrl);

        // Generate proof
        (bytes memory journal, bytes memory sealGenerated) = generateProof(ELF_PATH, input);
        
        // Decode journal to get purchase data
        // Treasury expects: (bytes32, string, string, bytes32)
        (
            bytes32 notaryKeyFingerprint,
            string memory method,
            string memory url,
            bytes32 queriesHash
        ) = abi.decode(journal, (bytes32, string, string, bytes32));
        
        // Re-encode as purchaseData for Treasury
        purchaseData = abi.encode(notaryKeyFingerprint, method, url, queriesHash);
        
        return (purchaseData, sealGenerated);
    }
}

