// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal view of the ERC 8004 Identity Registry on Celo.
/// @dev Ownership of the agent's identity NFT authorises activity submission.
interface IIdentityRegistry {
    function ownerOf(uint256 agentId) external view returns (address);
}

/// @notice Price source for converting a supported token amount into cUSD.
/// @dev Returns the cUSD value (18 decimals) of `amount` units of `token`.
///      On Celo this is backed by the Mento SortedOracles feed; in tests a
///      simple mock implements the same shape.
interface IPriceOracle {
    function toCUSD(address token, uint256 amount) external view returns (uint256);
}

/// @title AgentActivityOracle
/// @notice Verification engine for VisaProof. Agents submit proof of their
///         on chain transactions; the oracle records non duplicated tx hashes,
///         aggregates volume across supported Mento stablecoins into a single
///         cUSD denominated score, and exposes that score for tier computation.
contract AgentActivityOracle is Ownable {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    struct ActivityScore {
        uint256 totalVolumeCUSD;
        uint256 txCount;
        uint256 lastUpdated;
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice ERC 8004 Identity Registry used to authorise agent controllers.
    IIdentityRegistry public immutable identityRegistry;

    /// @notice Price oracle converting supported token volume into cUSD.
    IPriceOracle public priceOracle;

    /// @notice Tokens accepted in activity submissions (Mento stablecoins).
    mapping(address token => bool) public supportedToken;

    /// @notice List of supported tokens for off chain enumeration.
    address[] private _supportedTokens;

    /// @notice Aggregated score per agent.
    mapping(uint256 agentId => ActivityScore) private _scores;

    /// @notice Per agent set of tokens seen in submissions.
    mapping(uint256 agentId => address[]) private _verifiedTokens;
    mapping(uint256 agentId => mapping(address token => bool)) private _tokenSeen;

    /// @notice Global non duplication guard for submitted tx hashes.
    mapping(bytes32 txHash => bool) public consumedTxHash;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event TokenSupported(address indexed token, bool supported);
    event PriceOracleUpdated(address indexed oracle);
    event ActivitySubmitted(
        uint256 indexed agentId, address indexed submitter, uint256 newTxCount, uint256 addedVolumeCUSD
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error NotAgentOwner(uint256 agentId, address caller);
    error LengthMismatch();
    error EmptySubmission();
    error UnsupportedToken(address token);
    error DuplicateTxHash(bytes32 txHash);
    error ZeroTxHash();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address identityRegistry_, address priceOracle_, address owner_) Ownable(owner_) {
        if (identityRegistry_ == address(0) || priceOracle_ == address(0)) {
            revert ZeroAddress();
        }
        identityRegistry = IIdentityRegistry(identityRegistry_);
        priceOracle = IPriceOracle(priceOracle_);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Add or remove a token from the supported set.
    function setSupportedToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (supported && !supportedToken[token]) {
            _supportedTokens.push(token);
        } else if (!supported && supportedToken[token]) {
            _removeSupportedToken(token);
        }
        supportedToken[token] = supported;
        emit TokenSupported(token, supported);
    }

    /// @notice Update the price oracle used for cUSD conversion.
    function setPriceOracle(address priceOracle_) external onlyOwner {
        if (priceOracle_ == address(0)) revert ZeroAddress();
        priceOracle = IPriceOracle(priceOracle_);
        emit PriceOracleUpdated(priceOracle_);
    }

    // ---------------------------------------------------------------------
    // Mutating
    // ---------------------------------------------------------------------

    /// @notice Submit proof of an agent's transactions.
    /// @param agentId    ERC 8004 agent id. Caller must own its identity NFT.
    /// @param txHashes   Transaction hashes evidencing activity, must be unique.
    /// @param amounts    Token amounts moved in each transaction (token native units).
    /// @param tokens     Token contract addresses, one per tx hash, all supported.
    /// @dev Aggregates each amount into cUSD at the current oracle price and
    ///      increments the agent's tx count by the number of new hashes.
    function submitActivity(
        uint256 agentId,
        bytes32[] calldata txHashes,
        uint256[] calldata amounts,
        address[] calldata tokens
    ) external {
        _requireAgentOwner(agentId);

        uint256 n = txHashes.length;
        if (n == 0) revert EmptySubmission();
        if (amounts.length != n || tokens.length != n) revert LengthMismatch();

        uint256 addedVolume;
        for (uint256 i; i < n; ++i) {
            bytes32 txHash = txHashes[i];
            address token = tokens[i];

            if (txHash == bytes32(0)) revert ZeroTxHash();
            if (!supportedToken[token]) revert UnsupportedToken(token);
            if (consumedTxHash[txHash]) revert DuplicateTxHash(txHash);

            consumedTxHash[txHash] = true;
            addedVolume += priceOracle.toCUSD(token, amounts[i]);

            if (!_tokenSeen[agentId][token]) {
                _tokenSeen[agentId][token] = true;
                _verifiedTokens[agentId].push(token);
            }
        }

        ActivityScore storage s = _scores[agentId];
        s.totalVolumeCUSD += addedVolume;
        s.txCount += n;
        s.lastUpdated = block.timestamp;

        emit ActivitySubmitted(agentId, msg.sender, s.txCount, addedVolume);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Aggregated activity score for an agent.
    /// @dev Tuple shape matches IActivityOracle consumed by AgentPassport.
    function getActivityScore(uint256 agentId)
        external
        view
        returns (uint256 totalVolumeCUSD, uint256 txCount, uint256 lastUpdated)
    {
        ActivityScore memory s = _scores[agentId];
        return (s.totalVolumeCUSD, s.txCount, s.lastUpdated);
    }

    /// @notice Total cUSD denominated volume recorded for an agent.
    function aggregateVolume(uint256 agentId) external view returns (uint256) {
        return _scores[agentId].totalVolumeCUSD;
    }

    /// @notice Tokens an agent has submitted activity in.
    function verifiedTokens(uint256 agentId) external view returns (address[] memory) {
        return _verifiedTokens[agentId];
    }

    /// @notice Full supported token list.
    function supportedTokens() external view returns (address[] memory) {
        return _supportedTokens;
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _requireAgentOwner(uint256 agentId) private view {
        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert NotAgentOwner(agentId, msg.sender);
        }
    }

    function _removeSupportedToken(address token) private {
        uint256 len = _supportedTokens.length;
        for (uint256 i; i < len; ++i) {
            if (_supportedTokens[i] == token) {
                _supportedTokens[i] = _supportedTokens[len - 1];
                _supportedTokens.pop();
                return;
            }
        }
    }
}
