// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {Staking} from "@evvm/testnet-contracts/contracts/staking/Staking.sol";
import {Estimator} from "@evvm/testnet-contracts/contracts/staking/Estimator.sol";
import {NameService} from "@evvm/testnet-contracts/contracts/nameService/NameService.sol";
import {Treasury} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {P2PSwap} from "@evvm/testnet-contracts/contracts/p2pSwap/P2PSwap.sol";
import {EvvmStructs} from "@evvm/testnet-contracts/contracts/evvm/lib/EvvmStructs.sol";
import {MockUSDC} from "../../src/contracts/mocks/MockUSDC.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IRiscZeroVerifier} from "@risc0/contracts/IRiscZeroVerifier.sol";
import {NetworkConfig} from "../../script/NetworkConfig.sol";

/**
 * @title BaseTest
 * @notice Base test contract with common setup and utilities for all test suites
 */
abstract contract BaseTest is Test {
    // Core contracts
    Evvm public evvm;
    Staking public staking;
    Estimator public estimator;
    NameService public nameService;
    Treasury public treasury;
    P2PSwap public p2pSwap;

    // Mock contracts
    MockUSDC public usdc;
    MockERC20 public dai;
    
    // RISC Zero verifier (real contract on Base Sepolia)
    IRiscZeroVerifier public riscZeroVerifier;

    // Test accounts
    address public admin;
    address public activator;
    address public goldenFisher;
    address public alice;
    address public bob;
    address public charlie;
    address public executor;
    address public merchant;
    address public backend;

    // Private keys for signing
    uint256 public alicePrivateKey;
    uint256 public bobPrivateKey;
    uint256 public charliePrivateKey;
    uint256 public backendPrivateKey;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant PRINCIPAL_TOKEN_SUPPLY = 1_000_000_000 ether;
    
    // RISC Zero configuration constants (these should match your actual ZK proof program)
    // These are placeholder values - replace with actual values from your ZK proof setup
    bytes32 public constant RISC0_IMAGE_ID = bytes32(uint256(1)); // TODO: Replace with actual image ID
    bytes32 public constant RISC0_NOTARY_KEY_FINGERPRINT = bytes32(uint256(2)); // TODO: Replace with actual notary fingerprint
    bytes32 public constant RISC0_QUERIES_HASH = bytes32(uint256(3)); // TODO: Replace with actual queries hash

    function setUp() public virtual {
        // Fork Base Sepolia for testing
        vm.createSelectFork(NetworkConfig.BASE_SEPOLIA_RPC_URL);
        
        // Verify we're on Base Sepolia
        require(
            NetworkConfig.isBaseSepolia(block.chainid),
            "BaseTest: Must run tests on Base Sepolia fork"
        );
        
        // Get the real RISC Zero verifier router from Base Sepolia
        riscZeroVerifier = NetworkConfig.getRiscZeroVerifier();
        
        // Setup test accounts with specific addresses to avoid collisions
        admin = address(0x1234567890123456789012345678901234567890);
        activator = address(0x2345678901234567890123456789012345678901);
        goldenFisher = address(0x3456789012345678901234567890123456789012);
        executor = address(0x4567890123456789012345678901234567890123);
        merchant = address(0x5678901234567890123456789012345678901234);

        // Setup accounts with private keys for signing
        alicePrivateKey = 0xA11CE;
        bobPrivateKey = 0xB0B;
        charliePrivateKey = 0xC4A211E;
        backendPrivateKey = 0xBAC4E11D;

        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);
        charlie = vm.addr(charliePrivateKey);
        backend = vm.addr(backendPrivateKey);

        // Deploy mock tokens
        usdc = new MockUSDC();
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Deploy core contracts
        _deployCoreContracts();

        // Fund test accounts
        _fundTestAccounts();

        // Label contracts for better trace output
        _labelContracts();
    }

    function _deployCoreContracts() internal {
        // Prepare metadata for Evvm
        EvvmStructs.EvvmMetadata memory metadata = EvvmStructs.EvvmMetadata({
            EvvmName: "CypherMarket Testnet",
            EvvmID: 1,
            principalTokenName: "CypherMarket Token",
            principalTokenSymbol: "CYPHER",
            principalTokenAddress: address(0), // Will be set to Evvm address
            totalSupply: PRINCIPAL_TOKEN_SUPPLY,
            eraTokens: 100_000_000 ether,
            reward: 10 ether
        });

        // Deploy Staking first
        vm.prank(admin);
        staking = new Staking(admin, goldenFisher);

        // Deploy Evvm
        vm.prank(admin);
        evvm = new Evvm(admin, address(staking), metadata);

        // Deploy Estimator
        vm.prank(admin);
        estimator = new Estimator(activator, address(evvm), address(staking), admin);

        // Deploy NameService
        vm.prank(admin);
        nameService = new NameService(address(evvm), admin);

        // Deploy Treasury with real RISC Zero verifier
        vm.prank(admin);
        treasury = new Treasury(
            address(evvm),
            address(riscZeroVerifier),
            RISC0_IMAGE_ID,
            RISC0_NOTARY_KEY_FINGERPRINT,
            RISC0_QUERIES_HASH,
            address(usdc) // Payment token (USDC for tests)
        );

        // Setup connections
        vm.prank(admin);
        staking._setupEstimatorAndEvvm(address(estimator), address(evvm));

        vm.prank(admin);
        evvm._setupNameServiceAndTreasuryAddress(address(nameService), address(treasury));

        // Deploy P2PSwap
        vm.prank(admin);
        p2pSwap = new P2PSwap(address(evvm), address(staking), admin);
    }

    function _fundTestAccounts() internal {
        // Fund accounts with ETH
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(executor, INITIAL_BALANCE);
        vm.deal(merchant, INITIAL_BALANCE);

        // Mint mock tokens
        usdc.mint(alice, 10_000 * 10 ** 6); // 10,000 USDC
        usdc.mint(bob, 10_000 * 10 ** 6);
        usdc.mint(charlie, 10_000 * 10 ** 6);

        dai.mint(alice, 10_000 ether); // 10,000 DAI
        dai.mint(bob, 10_000 ether);
        dai.mint(charlie, 10_000 ether);

        // Mint principal tokens (CYPHER) via Evvm
        vm.startPrank(address(treasury));
        evvm.addAmountToUser(alice, address(evvm), 1000 ether);
        evvm.addAmountToUser(bob, address(evvm), 1000 ether);
        evvm.addAmountToUser(charlie, address(evvm), 1000 ether);
        vm.stopPrank();
    }

    function _labelContracts() internal {
        vm.label(address(evvm), "Evvm");
        vm.label(address(staking), "Staking");
        vm.label(address(estimator), "Estimator");
        vm.label(address(nameService), "NameService");
        vm.label(address(treasury), "Treasury");
        vm.label(address(p2pSwap), "P2PSwap");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(riscZeroVerifier), "RiscZeroVerifierRouter");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(admin, "Admin");
        vm.label(executor, "Executor");
        vm.label(merchant, "Merchant");
        vm.label(backend, "Backend");
    }

    // Helper functions for tests
    function signMessage(uint256 privateKey, bytes32 messageHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function signTransferAuthorization(
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

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", treasury.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);
    }

    function expectEmitAddress(address emitter) internal {
        vm.expectEmit(true, true, true, true, emitter);
    }
}
