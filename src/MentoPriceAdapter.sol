// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceOracle} from "./AgentActivityOracle.sol";

/// @notice Minimal view of Mento's SortedOracles price feed on Celo.
/// @dev `medianRate(token)` returns `(rate, denominator)` where
///      `rate / denominator` is the number of `token` units per 1 CELO.
///      Verified against Celo mainnet: denominator is 1e24, and the
///      cUSD:cEUR rate ratio matches the live EUR/USD exchange rate.
interface ISortedOracles {
    function medianRate(address rateFeedId) external view returns (uint256 rate, uint256 denominator);
}

/// @title MentoPriceAdapter
/// @notice Converts supported token amounts into an 18 decimal cUSD value for
///         AgentActivityOracle. Mento c-stables are priced through CELO using
///         SortedOracles; USD pegged bridged stables (USDT, USDC) and cUSD
///         itself are treated 1:1 with decimal normalisation.
contract MentoPriceAdapter is IPriceOracle, Ownable {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Mode {
        Unsupported,
        Pegged, // 1:1 with cUSD, decimal normalised (cUSD, USDT, USDC)
        Mento // routed through CELO via SortedOracles (cEUR, cREAL, ...)

    }

    struct TokenConfig {
        Mode mode;
        uint8 decimals;
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Mento SortedOracles feed used for c-stable conversion.
    ISortedOracles public sortedOracles;

    /// @notice cUSD address, the reference unit and a pegged token.
    address public immutable cUSD;

    mapping(address token => TokenConfig) public configOf;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event SortedOraclesUpdated(address indexed sortedOracles);
    event TokenConfigured(address indexed token, Mode mode, uint8 decimals);
    event TokenRemoved(address indexed token);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error UnsupportedToken(address token);
    error InvalidRate(address token);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address sortedOracles_, address cUSD_, address owner_) Ownable(owner_) {
        if (sortedOracles_ == address(0) || cUSD_ == address(0)) revert ZeroAddress();
        sortedOracles = ISortedOracles(sortedOracles_);
        cUSD = cUSD_;
        // cUSD is the reference: pegged 1:1, 18 decimals.
        configOf[cUSD_] = TokenConfig({mode: Mode.Pegged, decimals: 18});
        emit TokenConfigured(cUSD_, Mode.Pegged, 18);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Configure a token, reading its decimals from the token itself.
    function configureToken(address token, Mode mode) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (mode == Mode.Unsupported) revert UnsupportedToken(token);
        uint8 dec = IERC20Metadata(token).decimals();
        configOf[token] = TokenConfig({mode: mode, decimals: dec});
        emit TokenConfigured(token, mode, dec);
    }

    /// @notice Configure a token with an explicit decimals value.
    /// @dev For tokens that do not expose decimals() reliably.
    function configureTokenWithDecimals(address token, Mode mode, uint8 decimals_) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (mode == Mode.Unsupported) revert UnsupportedToken(token);
        configOf[token] = TokenConfig({mode: mode, decimals: decimals_});
        emit TokenConfigured(token, mode, decimals_);
    }

    /// @notice Remove a token from the supported set.
    function removeToken(address token) external onlyOwner {
        delete configOf[token];
        emit TokenRemoved(token);
    }

    /// @notice Update the SortedOracles feed address.
    function setSortedOracles(address sortedOracles_) external onlyOwner {
        if (sortedOracles_ == address(0)) revert ZeroAddress();
        sortedOracles = ISortedOracles(sortedOracles_);
        emit SortedOraclesUpdated(sortedOracles_);
    }

    // ---------------------------------------------------------------------
    // Conversion
    // ---------------------------------------------------------------------

    /// @inheritdoc IPriceOracle
    /// @notice cUSD value (18 decimals) of `amount` units of `token`.
    function toCUSD(address token, uint256 amount) external view returns (uint256) {
        TokenConfig memory cfg = configOf[token];
        if (cfg.mode == Mode.Unsupported) revert UnsupportedToken(token);

        // Normalise the raw token amount to 18 decimals.
        uint256 norm = _to18(amount, cfg.decimals);
        if (cfg.mode == Mode.Pegged) {
            return norm;
        }

        // Mento: value = norm * rate(cUSD) / rate(token), routed through CELO.
        (uint256 rTok, uint256 dTok) = sortedOracles.medianRate(token);
        (uint256 rUsd, uint256 dUsd) = sortedOracles.medianRate(cUSD);
        if (rTok == 0 || rUsd == 0) revert InvalidRate(token);

        uint256 step = Math.mulDiv(norm, rUsd, rTok);
        return Math.mulDiv(step, dTok, dUsd);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _to18(uint256 amount, uint8 decimals_) private pure returns (uint256) {
        if (decimals_ == 18) return amount;
        if (decimals_ < 18) return amount * (10 ** (18 - decimals_));
        return amount / (10 ** (decimals_ - 18));
    }
}
