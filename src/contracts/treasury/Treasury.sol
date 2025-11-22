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
    struct Listing {
        string url;
        uint256 amount;
        address shopper;
        bytes32 privateCredentials;
    }

    enum ShippingState {
        IN_TRANSIT,
        CANCELED,
        PENDING,
        DELIVERED
    }

    struct PrivateCredentialsRaw {
        string fullName;
        string emailAddress;
        string homeAddress;
        string city;
        string country;
        string zip;
    }

    mapping(bytes32 id => Listing listing) public fetchListing;
    mapping(address who => uint256 amount) locked;

    /// @notice Mapping of used nonces for transferWithAuthorization
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    /// @notice Custom errors
    error InvalidNotaryKeyFingerprint();
    error InvalidQueriesHash();
    error InvalidUrl();
    error ZKProofVerificationFailed();
    error InvalidContributions();
    error Expired();
    error InvalidListing();
    error AuthorizationAlreadyUsed();
    error InvalidSignature();
    error OrderWasntDelivered();
    error WrongCredentials();

    event ListingCreated(Listing listing, bytes32 id);
    event ListingFinalized(Listing listing, bytes32 id, address buyer);

    /// @notice ERC-3009 standard event
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

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

    address public immutable PAYMENT_TOKEN;

    /// @notice EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice EIP-712 typehash for transferWithAuthorization
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        keccak256(
            "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );

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
        address _paymentToken
    ) {
        evvmAddress = _evvmAddress;
        VERIFIER = IRiscZeroVerifier(_verifier);
        IMAGE_ID = _imageId;
        EXPECTED_NOTARY_KEY_FINGERPRINT = _expectedNotaryKeyFingerprint;
        EXPECTED_QUERIES_HASH = _expectedQueriesHash;
        PAYMENT_TOKEN = _paymentToken;

        // Initialize EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("Treasury")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Deposit ETH or ERC20 tokens
     * @param token ERC20 token address (ignored for ETH deposits)
     * @param amount Token amount (ignored for ETH deposits)
     */
    function deposit(address token, uint256 amount) external payable {
        depositFrom(msg.sender, token, amount);
    }

    function depositFrom(
        address depositor,
        address token,
        uint256 amount
    ) public payable {
        if (address(0) == token) {
            /// user is sending host native coin
            if (msg.value == 0) {
                revert ErrorsLib.DepositAmountMustBeGreaterThanZero();
            }
            if (amount != msg.value) revert ErrorsLib.InvalidDepositAmount();

            Evvm(evvmAddress).addAmountToUser(depositor, address(0), msg.value);
        } else {
            /// user is sending ERC20 tokens

            if (msg.value != 0) revert ErrorsLib.InvalidDepositAmount();
            if (amount == 0) {
                revert ErrorsLib.DepositAmountMustBeGreaterThanZero();
            }

            IERC20(token).transferFrom(depositor, address(this), amount);
            Evvm(evvmAddress).addAmountToUser(depositor, token, amount);
        }
    }

    /**
     * @notice Withdraw ETH or ERC20 tokens
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) internal {
        _withdraw(msg.sender, token, amount);
    }

    function _withdraw(address to, address token, uint256 amount) internal {
        if (
            token == Evvm(evvmAddress).getEvvmMetadata().principalTokenAddress
        ) {
            revert ErrorsLib.PrincipalTokenIsNotWithdrawable();
        }

        if (Evvm(evvmAddress).getBalance(to, token) - locked[to] < amount) {
            revert ErrorsLib.InsufficientBalance();
        }

        if (token == address(0)) {
            /// user is trying to withdraw native coin

            Evvm(evvmAddress).removeAmountFromUser(to, address(0), amount);
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            /// user is trying to withdraw ERC20 tokens

            Evvm(evvmAddress).removeAmountFromUser(to, token, amount);
            IERC20(token).transfer(to, amount);
        }
    }

    function list(Listing calldata listing) external {
        depositFrom(listing.shopper, PAYMENT_TOKEN, listing.amount);
        locked[listing.shopper] += listing.amount;
        bytes32 id = keccak256(abi.encode(listing));
        fetchListing[id] = listing;
        emit ListingCreated(listing, id);
    }

    function calculateId(
        Listing calldata listing
    ) external pure returns (bytes32 id) {
        id = keccak256(abi.encode(listing));
    }

    function createPrivateCredentials(PrivateCredentialsRaw calldata rawCredentials) external pure returns (bytes32 privateCredentials) {
        privateCredentials = keccak256(abi.encode(rawCredentials));
    }

    function submitPurchase(
        bytes32 id,
        bytes calldata purchaseData,
        bytes calldata seal
    ) external {
        (
            bytes32 notaryKeyFingerprint,
            string memory method,
            string memory url,
            bytes32 queriesHash,
            bytes32 privateCredentials,
            ShippingState shippingState
        ) = abi.decode(purchaseData, (bytes32, string, string, bytes32, bytes32, ShippingState));

        Listing memory listing = fetchListing[id];
        if (listing.shopper == address(0)) revert InvalidListing();

        // Validate notary key fingerprint
        if (notaryKeyFingerprint != EXPECTED_NOTARY_KEY_FINGERPRINT) {
            revert InvalidNotaryKeyFingerprint();
        }

        if (shippingState != ShippingState.DELIVERED) revert OrderWasntDelivered();
        if (privateCredentials != listing.privateCredentials) revert WrongCredentials();

        // Validate URL matches the expected endpoint pattern provided at deployment
        // The URL may include an API key parameter, so we check if it starts with the expected pattern
        bytes memory urlBytes = bytes(url);
        bytes memory patternBytes = bytes(listing.url);

        // Validate method is GET (expected for API calls)
        if (
            keccak256(bytes(method)) != keccak256(bytes("GET")) ||
            urlBytes.length < patternBytes.length
        ) {
            revert InvalidUrl();
        }

        // Compare the first part of the URL with the expected pattern
        for (uint256 i = 0; i < patternBytes.length; i++) {
            if (urlBytes[i] != patternBytes[i]) {
                revert InvalidUrl();
            }
        }

        // Validate queries hash
        if (queriesHash != EXPECTED_QUERIES_HASH) {
            revert InvalidQueriesHash();
        }

        // Validate URL equals the expected endpoint pattern provided at deployment
        if (keccak256(bytes(url)) != keccak256(bytes(listing.url))) {
            revert InvalidUrl();
        }

        // Verify the ZK proof
        try VERIFIER.verify(seal, IMAGE_ID, sha256(purchaseData)) {
            Evvm(evvmAddress).removeAmountFromUser(
                listing.shopper,
                PAYMENT_TOKEN,
                listing.amount
            );
            Evvm(evvmAddress).addAmountToUser(
                msg.sender,
                PAYMENT_TOKEN,
                listing.amount
            );
            delete fetchListing[id];
            locked[listing.shopper] -= listing.amount;
            emit ListingFinalized(listing, id, msg.sender);
        } catch {
            revert ZKProofVerificationFailed();
        }
    }

    /**
     * @notice CUSTOM x402-compatible payment release function
     * @dev This is NOT standard ERC-3009! Uses the signature for x402 compatibility,
     *      but implements custom behavior for marketplace escrow release:
     *      - `from` (backend) signs to authorize payment release
     *      - Withdraws from `to` (Bob) evvm balance to `to` wallet
     *      - Used after Bob proves Amazon purchase via ZK proof
     *      - Backend automatically signs and submits via x402 after proof verification
     * @param from The authorizer (backend address - signs the release)
     * @param to The recipient (Bob - receives the payout)
     * @param value Amount to withdraw
     * @param validAfter Timestamp after which authorization is valid
     * @param validBefore Timestamp before which authorization is valid
     * @param nonce Unique identifier to prevent replay attacks
     * @param v Signature component
     * @param r Signature component
     * @param s Signature component
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Check time validity
        uint256 timestamp = block.timestamp;
        if (timestamp < validAfter || timestamp > validBefore) revert Expired();

        // Check nonce hasn't been used
        if (authorizationState[from][nonce]) revert AuthorizationAlreadyUsed();

        // Construct the message hash according to EIP-712
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
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        // Recover signer from signature
        address signer = ecrecover(digest, v, r, s);

        // Verify signature is from 'from' address
        if (signer != from || signer == address(0)) revert InvalidSignature();

        // Mark nonce as used
        authorizationState[from][nonce] = true;

        _withdraw(to, PAYMENT_TOKEN, value);

        // Emit ERC-3009 event
        emit AuthorizationUsed(from, nonce);
    }
}
