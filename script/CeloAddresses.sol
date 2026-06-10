// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title CeloAddresses
/// @notice Canonical Celo mainnet addresses consumed by the deploy script.
/// @dev Each address was verified live against Celo mainnet (chain id 42220):
///      - SORTED_ORACLES: Mento price feed, medianRate denominator 1e24.
///      - IDENTITY_REGISTRY: ERC 8004 identity NFT (name "AgentIdentity",
///        symbol "AGENT"), an ERC 1967 proxy.
///      - cUSD/cEUR/cREAL: Mento stables (token addresses unchanged after the
///        USDm/EURm/BRLm symbol rebrand).
///      - USDT/USDC: bridged USD stables, 6 decimals, treated 1:1 with cUSD.
library CeloAddresses {
    address internal constant SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    /// @dev Self Agent ID registry (name "Self Agent ID", symbol "SAID"), an
    ///      ERC 1967 proxy. Soulbound ERC 721 binding agents to Self Protocol
    ///      proofs of human; read by AgentPassport to gate passport registration.
    address internal constant SELF_AGENT_REGISTRY = 0xaC3DF9ABf80d0F5c020C06B04Cced27763355944;

    address internal constant cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address internal constant cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
    address internal constant cREAL = 0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787;

    address internal constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;
    address internal constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;
}
