// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for mintable tokens (like MockUSDC)
interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title List
/// @notice Script to create a listing on the Treasury contract
contract List is Script {
    // Paths for deployment tracking
    string public PATH_PREFIX;
    string public TREASURY_PATH;
    string public TREASURY_FILE;
    string public LISTINGS_PATH;
    string public LISTING_FILE;
    string public CREDENTIALS_FILE;

    constructor() {
        // Setup paths based on chain ID
        PATH_PREFIX = string.concat("deployments/", vm.toString(block.chainid));
        _setupPaths();
    }

    function _setupPaths() internal {
        TREASURY_PATH = string.concat(PATH_PREFIX, "/Treasury/");
        TREASURY_FILE = string.concat(TREASURY_PATH, "address.json");
        LISTINGS_PATH = string.concat(PATH_PREFIX, "/Listings/");

        // Create directories if they don't exist
        if (!vm.isDir(TREASURY_PATH)) {
            vm.createDir(TREASURY_PATH, true);
        }
        if (!vm.isDir(LISTINGS_PATH)) {
            vm.createDir(LISTINGS_PATH, true);
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

            // Save for future use using vm.serialize*
            string memory objectKey = "treasury";
            string memory json = vm.serializeAddress(objectKey, "address", treasuryAddress);
            json = vm.serializeUint(objectKey, "chainId", block.chainid);
            json = vm.serializeUint(objectKey, "deployedAt", block.timestamp);
            vm.writeJson(json, TREASURY_FILE);
            console2.log("Saved Treasury address:", treasuryAddress);
        }

        Treasury treasury = Treasury(treasuryAddress);

        // Get listing parameters - use hardcoded dummy data by default
        string memory url = vm.envOr("LISTING_URL", string("https://www.amazon.com/gp/your-account/order-details/?orderID=111-1234567-8901234"));
        uint256 amount = vm.envOr("LISTING_AMOUNT", uint256(100000000)); // Default: 100 USDC (6 decimals)
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

        // Generate unique filename for this listing using timestamp and shopper
        uint256 timestamp = block.timestamp;
        string memory listingFileName = string.concat(
            "listing_",
            vm.toString(timestamp),
            "_",
            vm.toString(shopper)
        );
        LISTING_FILE = string.concat(LISTINGS_PATH, listingFileName, ".json");
        CREDENTIALS_FILE = string.concat(LISTINGS_PATH, listingFileName, "_credentials.txt");

        console2.log("Creating listing:");
        console2.log("  URL:", listing.url);
        console2.log("  Amount:", listing.amount);
        console2.log("  Shopper:", listing.shopper);
        console2.log("  Listing ID:", vm.toString(listingId));
        console2.log("  Timestamp:", timestamp);

        // Get payment token address
        address paymentToken = treasury.PAYMENT_TOKEN();
        
        // Start broadcast for both approval and listing
        vm.startBroadcast();
        
        // Approve payment token if needed (for ERC20)
        if (paymentToken != address(0)) {
            IERC20 token = IERC20(paymentToken);
            uint256 allowance = token.allowance(shopper, address(treasury));
            
            if (allowance < amount) {
                console2.log("Approving payment token...");
                token.approve(address(treasury), amount);
                console2.log("Approved", amount, "tokens");
            }
        }

        // Create the listing
        treasury.list(listing);
        
        vm.stopBroadcast();

        // Save listing data for future reference
        _saveListingData(listing, listingId, privateCredentials, address(treasury));

        console2.log("\nListing created successfully!");
        console2.log("Listing ID:", vm.toString(listingId));
        console2.log("Listing data saved to:", LISTING_FILE);
        console2.log("Private credentials saved to:", CREDENTIALS_FILE);
    }

    /// @notice Save listing data to JSON file
    function _saveListingData(
        Treasury.Listing memory listing,
        bytes32 listingId,
        bytes32 privateCredentials,
        address treasuryAddress
    ) internal {
        // Create JSON object with listing data using vm.serialize*
        string memory objectKey = "listing";
        string memory json = vm.serializeBytes32(objectKey, "listingId", listingId);
        json = vm.serializeString(objectKey, "url", listing.url);
        json = vm.serializeUint(objectKey, "amount", listing.amount);
        json = vm.serializeAddress(objectKey, "shopper", listing.shopper);
        json = vm.serializeBytes32(objectKey, "privateCredentials", privateCredentials);
        json = vm.serializeUint(objectKey, "timestamp", block.timestamp);
        json = vm.serializeUint(objectKey, "chainId", block.chainid);
        json = vm.serializeAddress(objectKey, "treasuryAddress", treasuryAddress);

        // Write JSON file
        vm.writeJson(json, LISTING_FILE);

        // Also save just the private credentials in a separate file for easy reference
        vm.writeFile(CREDENTIALS_FILE, vm.toString(privateCredentials));

        // Create a "latest" symlink-like file pointing to this listing
        string memory latestFile = string.concat(LISTINGS_PATH, "latest_listing.json");
        vm.writeJson(json, latestFile);

        console2.log("\nSaved listing data:");
        console2.log("  Listing file:", LISTING_FILE);
        console2.log("  Credentials file:", CREDENTIALS_FILE);
        console2.log("  Latest listing:", latestFile);
    }
}

