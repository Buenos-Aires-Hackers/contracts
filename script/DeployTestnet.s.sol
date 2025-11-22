// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {Staking} from "@evvm/testnet-contracts/contracts/staking/Staking.sol";
import {Estimator} from "@evvm/testnet-contracts/contracts/staking/Estimator.sol";
import {NameService} from "@evvm/testnet-contracts/contracts/nameService/NameService.sol";
import {EvvmStructs} from "@evvm/testnet-contracts/contracts/evvm/lib/EvvmStructs.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {P2PSwap} from "@evvm/testnet-contracts/contracts/p2pSwap/P2PSwap.sol";
import {MockUSDC} from "../src/contracts/mocks/MockUSDC.sol";
import {NetworkConfig} from "./NetworkConfig.sol";

contract DeployTestnet is Script {
    Staking staking;
    Evvm evvm;
    Estimator estimator;
    NameService nameService;
    Treasury treasury;
    P2PSwap p2pSwap;
    MockUSDC usdc;

    struct AddressData {
        address activator;
        address admin;
        address goldenFisher;
    }

    struct BasicMetadata {
        string EvvmName;
        string principalTokenName;
        string principalTokenSymbol;
    }

    struct AdvancedMetadata {
        uint256 eraTokens;
        uint256 reward;
        uint256 totalSupply;
    }

    function setUp() public {}

    function run() public {
        // Verify we're on Base Sepolia
        require(
            NetworkConfig.isBaseSepolia(block.chainid),
            "DeployTestnet: Must deploy to Base Sepolia (chain ID 84532)"
        );

        string memory path = "input/address.json";
        assert(vm.isFile(path));
        string memory data = vm.readFile(path);
        bytes memory dataJson = vm.parseJson(data);

        AddressData memory addressData = abi.decode(dataJson, (AddressData));

        path = "input/evvmBasicMetadata.json";
        assert(vm.isFile(path));
        data = vm.readFile(path);
        dataJson = vm.parseJson(data);

        BasicMetadata memory basicMetadata = abi.decode(dataJson, (BasicMetadata));

        path = "input/evvmAdvancedMetadata.json";
        assert(vm.isFile(path));
        data = vm.readFile(path);
        dataJson = vm.parseJson(data);

        AdvancedMetadata memory advancedMetadata = abi.decode(dataJson, (AdvancedMetadata));

        // Get RISC Zero verifier configuration from environment variables
        address risc0Verifier = NetworkConfig.RISC_ZERO_VERIFIER_ROUTER;
        bytes32 imageId = vm.envOr("RISC0_IMAGE_ID", bytes32(0));
        bytes32 notaryKeyFingerprint = vm.envOr("NOTARY_KEY_FINGERPRINT", bytes32(0));
        bytes32 queriesHash = vm.envOr("QUERIES_HASH", bytes32(0));
        // Use provided payment token address, or deploy MockUSDC if not provided
        address paymentToken = vm.envOr("PAYMENT_TOKEN_ADDRESS", address(0));

        // Validate parameters (following pattern from zk-github-contribution-verifier)
        require(imageId != bytes32(0), "RISC0_IMAGE_ID not set");
        require(notaryKeyFingerprint != bytes32(0), "RISC0_NOTARY_KEY_FINGERPRINT not set");
        require(queriesHash != bytes32(0), "RISC0_QUERIES_HASH not set");

        console2.log("Deploying to Base Sepolia (chain ID:", block.chainid, ")");
        console2.log("Admin:", addressData.admin);
        console2.log("GoldenFisher:", addressData.goldenFisher);
        console2.log("Activator:", addressData.activator);
        console2.log("EvvmName:", basicMetadata.EvvmName);
        console2.log("PrincipalTokenName:", basicMetadata.principalTokenName);
        console2.log("PrincipalTokenSymbol:", basicMetadata.principalTokenSymbol);
        console2.log("TotalSupply:", advancedMetadata.totalSupply);
        console2.log("EraTokens:", advancedMetadata.eraTokens);
        console2.log("Reward:", advancedMetadata.reward);
        console2.log("RISC Zero Verifier Router:", risc0Verifier);
        console2.log("Image ID:");
        console2.logBytes32(imageId);
        console2.log("Notary Key Fingerprint:");
        console2.logBytes32(notaryKeyFingerprint);
        console2.log("Queries Hash:");
        console2.logBytes32(queriesHash);
        console2.log("Payment Token:", paymentToken);

        EvvmStructs.EvvmMetadata memory inputMetadata = EvvmStructs.EvvmMetadata({
            EvvmName: basicMetadata.EvvmName,
            EvvmID: 0,
            ///@dev dont change the EvvmID unless you know what you are doing
            principalTokenName: basicMetadata.principalTokenName,
            principalTokenSymbol: basicMetadata.principalTokenSymbol,
            principalTokenAddress: 0x0000000000000000000000000000000000000001,
            totalSupply: advancedMetadata.totalSupply,
            eraTokens: advancedMetadata.eraTokens,
            reward: advancedMetadata.reward
        });

        vm.startBroadcast();

        // Deploy MockUSDC if payment token not provided
        if (paymentToken == address(0)) {
            usdc = new MockUSDC();
            paymentToken = address(usdc);
            console2.log("MockUSDC deployed at:", address(usdc));
        }

        staking = new Staking(addressData.admin, addressData.goldenFisher);
        evvm = new Evvm(addressData.admin, address(staking), inputMetadata);
        estimator = new Estimator(addressData.activator, address(evvm), address(staking), addressData.admin);
        nameService = new NameService(address(evvm), addressData.admin);

        treasury = new Treasury(
            address(evvm),
            risc0Verifier,
            imageId,
            notaryKeyFingerprint,
            queriesHash,
            paymentToken
        );

        staking._setupEstimatorAndEvvm(address(estimator), address(evvm));
        evvm._setupNameServiceAndTreasuryAddress(address(nameService), address(treasury));

        p2pSwap = new P2PSwap(address(evvm), address(staking), addressData.admin);
        vm.stopBroadcast();

        console2.log("Staking deployed at:", address(staking));
        console2.log("Evvm deployed at:", address(evvm));
        console2.log("Estimator deployed at:", address(estimator));
        console2.log("NameService deployed at:", address(nameService));
        console2.log("Treasury deployed at:", address(treasury));
        console2.log("P2PSwap deployed at:", address(p2pSwap));
        console2.log("Payment Token (USDC):", paymentToken);
    }
}
