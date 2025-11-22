// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title SubmitPurchaseWithWebProof
/// @notice Script to submit a purchase by first compressing a web proof via vlayer API
/// @dev Uses FFI to call external script that interacts with vlayer API
contract SubmitPurchaseWithWebProof is Script {
    using stdJson for string;

    // Paths for deployment tracking
    string public PATH_PREFIX;
    string public TREASURY_PATH;
    string public TREASURY_FILE;
    string public LISTINGS_PATH;
    string public PURCHASES_PATH;
    string public PURCHASE_FILE;

    struct VlayerResponse {
        bytes zkProof;
        bytes journalDataAbi;
    }

    struct JournalData {
        bytes32 notaryKeyFingerprint;
        string method;
        string url;
        uint256 timestamp;
        bytes32 queriesHash;
        bytes extractedValues;
    }

    struct ListingData {
        bytes32 listingId;
        string url;
        uint256 amount;
        address shopper;
        bytes32 privateCredentials;
        uint256 timestamp;
        uint256 chainId;
        address treasuryAddress;
    }

    constructor() {
        // Setup paths based on chain ID
        PATH_PREFIX = string.concat("deployments/", vm.toString(block.chainid));
        _setupPaths();
    }

    function _setupPaths() internal {
        TREASURY_PATH = string.concat(PATH_PREFIX, "/Treasury/");
        TREASURY_FILE = string.concat(TREASURY_PATH, "address.json");
        LISTINGS_PATH = string.concat(PATH_PREFIX, "/Listings/");
        PURCHASES_PATH = string.concat(PATH_PREFIX, "/Purchases/");

        // Create directories if they don't exist
        if (!vm.isDir(PURCHASES_PATH)) {
            vm.createDir(PURCHASES_PATH, true);
        }
    }

    function run() external {
        // Get Treasury address - try deployments.json first, then Treasury/address.json, then env
        address treasuryAddress;
        string memory deploymentsFile = string.concat(PATH_PREFIX, "/deployments.json");

        if (vm.isFile(deploymentsFile)) {
            string memory json = vm.readFile(deploymentsFile);
            treasuryAddress = vm.parseJsonAddress(json, ".treasury");
            console2.log("Using Treasury address from deployments.json:", treasuryAddress);
        } else if (vm.isFile(TREASURY_FILE)) {
            string memory json = vm.readFile(TREASURY_FILE);
            treasuryAddress = vm.parseJsonAddress(json, ".address");
            console2.log("Using Treasury address from Treasury/address.json:", treasuryAddress);
        } else {
            treasuryAddress = vm.envOr("TREASURY_ADDRESS", address(0));
            require(treasuryAddress != address(0), "TREASURY_ADDRESS not set and no saved address found");
        }

        Treasury treasury = Treasury(treasuryAddress);

        // Load listing data from file or environment
        ListingData memory listingData = _loadListingData();

        console2.log("\nLoaded listing data:");
        console2.log("  Listing ID:", vm.toString(listingData.listingId));
        console2.log("  URL:", listingData.url);
        console2.log("  Amount:", listingData.amount);
        console2.log("  Shopper:", listingData.shopper);
        console2.log("  Private Credentials:", vm.toString(listingData.privateCredentials));

        // Use the listing URL for web proof generation (must match the listing)
        // For testing: use Binance API URL if listing URL is Amazon (which requires auth)
        string memory webProofPath = listingData.url;
        
        // Check if listing URL is Amazon (which requires authentication)
        bool isAmazonUrl = _startsWith(listingData.url, "https://www.amazon.com");
        
        // For testing: if Amazon URL, use Binance API instead
        if (isAmazonUrl) {
            webProofPath = "https://data-api.binance.vision/api/v3/ticker/price?symbol=ETHUSDC";
            console2.log("WARNING: Amazon URL requires authentication, using Binance API for testing:");
            console2.log("  Test URL:", webProofPath);
            console2.log("  Listing URL:", listingData.url);
        } else {
            console2.log("Using listing URL for web proof:", webProofPath);
        }
        
        // Allow override via WEB_PROOF_URL environment variable
        string memory envWebProofUrl = vm.envOr("WEB_PROOF_URL", string(""));
        if (bytes(envWebProofUrl).length > 0) {
            webProofPath = envWebProofUrl;
            console2.log("Using WEB_PROOF_URL override:", webProofPath);
        }

        // Get shipping state from extraction or environment
        uint8 shippingStateRaw = uint8(vm.envOr("SHIPPING_STATE", uint256(3))); // Default to DELIVERED
        require(shippingStateRaw <= 3, "Invalid shipping state (0-3)");
        Treasury.ShippingState shippingState = Treasury.ShippingState(shippingStateRaw);

        // Define extraction queries for the web proof
        // For Binance API, extract price and symbol
        // For Amazon, would extract orderStatus (but we're using Binance for testing)
        string memory extractionQueries = vm.envOr(
            "EXTRACTION_QUERIES",
            string('{"response.body": {"jmespath": ["price", "symbol"]}}')
        );

        console2.log("Compressing web proof...");
        console2.log("  Web proof path:", webProofPath);
        console2.log("  Extraction queries:", extractionQueries);

        // Call vlayer API via FFI
        VlayerResponse memory vlayerResponse = compressWebProof(webProofPath, extractionQueries);

        console2.log("Web proof compressed successfully!");
        console2.log("  ZK Proof length:", vlayerResponse.zkProof.length);
        console2.log("  Journal data length:", vlayerResponse.journalDataAbi.length);

        // Decode the journal data
        JournalData memory journalData = decodeJournalData(vlayerResponse.journalDataAbi);

        console2.log("\nJournal Data:");
        console2.log("  Notary Key Fingerprint:");
        console2.logBytes32(journalData.notaryKeyFingerprint);
        console2.log("  Method:", journalData.method);
        console2.log("  URL:", journalData.url);
        console2.log("  Timestamp:", journalData.timestamp);
        console2.log("  Queries Hash:");
        console2.logBytes32(journalData.queriesHash);

        // Verify this matches the Treasury's expected values
        bytes32 expectedNotaryFingerprint = treasury.EXPECTED_NOTARY_KEY_FINGERPRINT();
        bytes32 expectedQueriesHash = treasury.EXPECTED_QUERIES_HASH();

        console2.log("\nValidation:");
        console2.log("  Expected Notary Fingerprint:");
        console2.logBytes32(expectedNotaryFingerprint);
        console2.log("  Expected Queries Hash:");
        console2.logBytes32(expectedQueriesHash);

        require(
            journalData.notaryKeyFingerprint == expectedNotaryFingerprint,
            "Notary fingerprint mismatch"
        );
        
        // Provide detailed error message for queries hash mismatch
        if (journalData.queriesHash != expectedQueriesHash) {
            console2.log("\nERROR: Queries hash mismatch!");
            console2.log("  The extraction queries used don't match what was set during Treasury deployment.");
            console2.log("  Extraction queries used:", extractionQueries);
            console2.log("  Expected queries hash:");
            console2.logBytes32(expectedQueriesHash);
            console2.log("  Actual queries hash from web proof:");
            console2.logBytes32(journalData.queriesHash);
            console2.log("\n  To fix this:");
            console2.log("  1. Check what extraction queries were used during Treasury deployment");
            console2.log("  2. Use the EXACT same extraction queries format (JSON must match exactly)");
            console2.log("  3. The queries hash is computed by vlayer from the extraction queries JSON");
            revert("Queries hash mismatch - extraction queries must match Treasury deployment");
        }

        // Encode purchase data for the Treasury contract
        // Format: (notaryKeyFingerprint, method, url, queriesHash, privateCredentials, shippingState)
        bytes memory purchaseData = abi.encode(
            journalData.notaryKeyFingerprint,
            journalData.method,
            journalData.url,
            journalData.queriesHash,
            listingData.privateCredentials,
            shippingState
        );

        console2.log("\nSubmitting purchase:");
        console2.log("  Listing ID:", vm.toString(listingData.listingId));
        console2.log("  Private Credentials:");
        console2.logBytes32(listingData.privateCredentials);
        console2.log("  Shipping State:", uint256(shippingState));

        // Submit the purchase
        vm.startBroadcast();
        treasury.submitPurchase(listingData.listingId, purchaseData, vlayerResponse.zkProof);
        vm.stopBroadcast();

        // Save purchase data
        _savePurchaseData(listingData, journalData, msg.sender, shippingState);

        console2.log("\nPurchase submitted successfully!");
        console2.log("Purchase data saved to:", PURCHASE_FILE);
    }

    /// @notice Load listing data from saved JSON file
    function _loadListingData() internal returns (ListingData memory) {
        // Try to load from environment-specified file first
        string memory listingFile = vm.envOr("LISTING_FILE", string(""));

        // If not specified, try to load from latest
        if (bytes(listingFile).length == 0) {
            listingFile = string.concat(LISTINGS_PATH, "latest_listing.json");
        }

        require(vm.isFile(listingFile), string.concat("Listing file not found: ", listingFile));

        string memory json = vm.readFile(listingFile);

        // Parse JSON fields
        bytes32 listingId = vm.parseJsonBytes32(json, ".listingId");
        string memory url = vm.parseJsonString(json, ".url");
        uint256 amount = vm.parseJsonUint(json, ".amount");
        address shopper = vm.parseJsonAddress(json, ".shopper");
        bytes32 privateCredentials = vm.parseJsonBytes32(json, ".privateCredentials");
        uint256 timestamp = vm.parseJsonUint(json, ".timestamp");
        uint256 chainId = vm.parseJsonUint(json, ".chainId");
        address treasuryAddress = vm.parseJsonAddress(json, ".treasuryAddress");

        console2.log("Loaded listing from:", listingFile);

        return ListingData({
            listingId: listingId,
            url: url,
            amount: amount,
            shopper: shopper,
            privateCredentials: privateCredentials,
            timestamp: timestamp,
            chainId: chainId,
            treasuryAddress: treasuryAddress
        });
    }

    /// @notice Save purchase data to JSON file
    function _savePurchaseData(
        ListingData memory listingData,
        JournalData memory journalData,
        address merchant,
        Treasury.ShippingState shippingState
    ) internal {
        // Generate unique filename for this purchase
        uint256 timestamp = block.timestamp;
        string memory purchaseFileName = string.concat(
            "purchase_",
            vm.toString(timestamp),
            "_",
            vm.toString(listingData.listingId)
        );
        PURCHASE_FILE = string.concat(PURCHASES_PATH, purchaseFileName, ".json");

        // Create JSON object with purchase data using vm.serialize*
        string memory objectKey = "purchase";
        string memory json = vm.serializeBytes32(objectKey, "listingId", listingData.listingId);
        json = vm.serializeAddress(objectKey, "merchant", merchant);
        json = vm.serializeAddress(objectKey, "shopper", listingData.shopper);
        json = vm.serializeUint(objectKey, "amount", listingData.amount);
        json = vm.serializeString(objectKey, "url", journalData.url);
        json = vm.serializeBytes32(objectKey, "notaryKeyFingerprint", journalData.notaryKeyFingerprint);
        json = vm.serializeBytes32(objectKey, "queriesHash", journalData.queriesHash);
        json = vm.serializeUint(objectKey, "shippingState", uint256(shippingState));
        json = vm.serializeUint(objectKey, "timestamp", timestamp);
        json = vm.serializeUint(objectKey, "proofTimestamp", journalData.timestamp);
        json = vm.serializeUint(objectKey, "chainId", block.chainid);
        json = vm.serializeAddress(objectKey, "treasuryAddress", listingData.treasuryAddress);

        // Write JSON file
        vm.writeJson(json, PURCHASE_FILE);

        console2.log("\nSaved purchase data:");
        console2.log("  Purchase file:", PURCHASE_FILE);
    }

    /// @notice Compress web proof using vlayer API via FFI
    /// @param webProofPath Path to the web proof JSON file
    /// @param extractionQueries JSON string of extraction queries
    /// @return VlayerResponse containing zkProof and journalDataAbi
    function compressWebProof(
        string memory webProofPath,
        string memory extractionQueries
    ) internal returns (VlayerResponse memory) {
        // Prepare FFI command
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "script/helpers/compress_web_proof.sh";
        inputs[2] = webProofPath;

        // Write extraction queries to temp file
        string memory tempQueriesPath = string.concat(vm.projectRoot(), "/script/helpers/.temp_queries.json");
        vm.writeFile(tempQueriesPath, extractionQueries);

        // Update inputs to include queries file
        string[] memory fullInputs = new string[](4);
        fullInputs[0] = "bash";
        fullInputs[1] = "script/helpers/compress_web_proof.sh";
        fullInputs[2] = webProofPath;
        fullInputs[3] = tempQueriesPath;

        // Execute FFI
        bytes memory result = vm.ffi(fullInputs);
        string memory resultStr = string(result);

        // Clean up temp file
        vm.removeFile(tempQueriesPath);

        // Parse JSON response
        bytes memory zkProof = vm.parseJsonBytes(resultStr, ".zkProof");
        bytes memory journalDataAbi = vm.parseJsonBytes(resultStr, ".journalDataAbi");

        return VlayerResponse({
            zkProof: zkProof,
            journalDataAbi: journalDataAbi
        });
    }

    /// @notice Check if a string starts with a prefix
    /// @param str The string to check
    /// @param prefix The prefix to check for
    /// @return True if string starts with prefix
    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) {
            return false;
        }
        
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }

    /// @notice Decode journal data from ABI-encoded bytes
    /// @param journalDataAbi ABI-encoded journal data from vlayer
    /// @return JournalData struct
    function decodeJournalData(bytes memory journalDataAbi) internal pure returns (JournalData memory) {
        // vlayer returns: (notaryKeyFingerprint, method, url, timestamp, queriesHash, extractedValues[])
        (
            bytes32 notaryKeyFingerprint,
            string memory method,
            string memory url,
            uint256 timestamp,
            bytes32 queriesHash,
            bytes memory extractedValues
        ) = abi.decode(journalDataAbi, (bytes32, string, string, uint256, bytes32, bytes));

        return JournalData({
            notaryKeyFingerprint: notaryKeyFingerprint,
            method: method,
            url: url,
            timestamp: timestamp,
            queriesHash: queriesHash,
            extractedValues: extractedValues
        });
    }
}
