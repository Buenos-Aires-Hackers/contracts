// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity 0.8.30;

/**
 * ░██████████
 *     ░██
 *     ░█░██░███░███████░██████ ░███████░██    ░█░██░███░██    ░██
 *     ░█░███  ░██    ░██    ░█░██      ░██    ░█░███   ░██    ░██
 *     ░█░██   ░████████░███████░███████░██    ░█░██    ░██    ░██
 *     ░█░██   ░██     ░██   ░██      ░█░██   ░██░██    ░██   ░███
 *     ░█░██    ░███████░█████░█░███████ ░█████░█░██     ░█████░██
 *                                                             ░██
 *                                                       ░███████
 *
 * ████████╗███████╗███████╗████████╗███╗   ██╗███████╗████████╗
 * ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝████╗  ██║██╔════╝╚══██╔══╝
 *    ██║   █████╗  ███████╗   ██║   ██╔██╗ ██║█████╗     ██║
 *    ██║   ██╔══╝  ╚════██║   ██║   ██║╚██╗██║██╔══╝     ██║
 *    ██║   ███████╗███████║   ██║   ██║ ╚████║███████╗   ██║
 *    ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝
 *
 * @title Treasury Contract
 * @author Mate labs
 * @notice Treasury for managing deposits and withdrawals in the EVVM ecosystem
 * @dev Secure vault for ETH and ERC20 tokens with EVVM integration and input validation
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {Evvm} from "@evvm/testnet-contracts/contracts/evvm/Evvm.sol";
import {ErrorsLib} from "@evvm/testnet-contracts/contracts/treasury/lib/ErrorsLib.sol";
import {IRiscZeroVerifier} from "@risc0/contracts/IRiscZeroVerifier.sol";

contract Treasury {
    struct Allowance {
        uint256 amount;
        uint256 validUntil;
    }

    /// @notice Custom errors
    error InvalidNotaryKeyFingerprint();
    error InvalidQueriesHash();
    error InvalidUrl();
    error ZKProofVerificationFailed();
    error InvalidContributions();

    mapping(address who => mapping(address token => Allowance info))
        public allowedAmountOf;

    /// @notice Address of the EVVM core contract
    address public evvmAddress;

    /// @notice RISC Zero verifier contract
    IRiscZeroVerifier public immutable VERIFIER;

    /// @notice ZK proof program identifier
    /// @dev This should match the IMAGE_ID from your ZK proof program
    bytes32 public immutable IMAGE_ID;

    /// @notice Expected notary key fingerprint from vlayer
    bytes32 public immutable EXPECTED_NOTARY_KEY_FINGERPRINT;

    /// @notice Expected queries hash - validates correct fields are extracted
    /// @dev Computed from the JMESPath queries used to extract balance
    bytes32 public immutable EXPECTED_QUERIES_HASH;

    /// @notice Expected URL pattern for Etherscan API
    string public expectedUrlPattern;

    /**
     * @notice Initialize Treasury with EVVM contract address
     * @param _evvmAddress Address of the EVVM core contract
     */
    constructor(
        address _evvmAddress,
        address _verifier,
        bytes32 _imageId,
        bytes32 _expectedNotaryKeyFingerprint,
        bytes32 _expectedQueriesHash,
        string memory _expectedUrlPattern
    ) {
        evvmAddress = _evvmAddress;
        VERIFIER = IRiscZeroVerifier(_verifier);
        IMAGE_ID = _imageId;
        EXPECTED_NOTARY_KEY_FINGERPRINT = _expectedNotaryKeyFingerprint;
        EXPECTED_QUERIES_HASH = _expectedQueriesHash;
        expectedUrlPattern = _expectedUrlPattern;
    }

    /**
     * @notice Deposit ETH or ERC20 tokens
     * @param token ERC20 token address (ignored for ETH deposits)
     * @param amount Token amount (ignored for ETH deposits)
     */
    function deposit(address token, uint256 amount) external payable {
        if (address(0) == token) {
            /// user is sending host native coin
            if (msg.value == 0) {
                revert ErrorsLib.DepositAmountMustBeGreaterThanZero();
            }
            if (amount != msg.value) revert ErrorsLib.InvalidDepositAmount();

            Evvm(evvmAddress).addAmountToUser(
                msg.sender,
                address(0),
                msg.value
            );
        } else {
            /// user is sending ERC20 tokens

            if (msg.value != 0) revert ErrorsLib.InvalidDepositAmount();
            if (amount == 0) {
                revert ErrorsLib.DepositAmountMustBeGreaterThanZero();
            }

            IERC20(token).transferFrom(msg.sender, address(this), amount);
            Evvm(evvmAddress).addAmountToUser(msg.sender, token, amount);
        }
    }

    /**
     * @notice Withdraw ETH or ERC20 tokens
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external {
        if (
            token == Evvm(evvmAddress).getEvvmMetadata().principalTokenAddress
        ) {
            revert ErrorsLib.PrincipalTokenIsNotWithdrawable();
        }

        if (Evvm(evvmAddress).getBalance(msg.sender, token) < amount) {
            revert ErrorsLib.InsufficientBalance();
        }

        if (token == address(0)) {
            /// user is trying to withdraw native coin

            Evvm(evvmAddress).removeAmountFromUser(
                msg.sender,
                address(0),
                amount
            );
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            /// user is trying to withdraw ERC20 tokens

            Evvm(evvmAddress).removeAmountFromUser(msg.sender, token, amount);
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    function submitPurchase(
        address shopper,
        address token,
        uint256 amount,
        bytes calldata purchaseData,
        bytes calldata seal
    ) external {
        (
            bytes32 notaryKeyFingerprint,
            string memory _method,
            string memory url,
            uint256 timestamp,
            bytes32 queriesHash
        ) = abi.decode(
                purchaseData,
                (bytes32, string, string, uint256, bytes32)
            );

        // Validate notary key fingerprint
        if (notaryKeyFingerprint != EXPECTED_NOTARY_KEY_FINGERPRINT) {
            revert InvalidNotaryKeyFingerprint();
        }

        // Validate queries hash
        if (queriesHash != EXPECTED_QUERIES_HASH) {
            revert InvalidQueriesHash();
        }

        // Validate URL equals the expected endpoint pattern provided at deployment
        if (keccak256(bytes(url)) != keccak256(bytes(expectedUrlPattern))) {
            revert InvalidUrl();
        }

        // Verify the ZK proof
        try VERIFIER.verify(seal, IMAGE_ID, sha256(purchaseData)) {
            // Proof verified successfully
        } catch {
            revert ZKProofVerificationFailed();
        }
    }
}
