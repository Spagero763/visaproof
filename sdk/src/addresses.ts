import type { Address } from "viem";

/**
 * Deployed VisaProof contract addresses on Celo mainnet (chain id 42220).
 *
 * This is the proof-of-human v2 stack: `AgentPassport.registerAgent(agentId,
 * selfAgentId)` is gated on a Self Agent ID. Pass `contracts` to the
 * {@link VisaProof} constructor to override any address (e.g. a local fork).
 */
export interface VisaProofContracts {
  /** AgentPassport, tier tracker, gated on a Self Agent ID proof of human. */
  passport: Address;
  /** AgentActivityOracle, records tx hashes, aggregates multi-token volume. */
  activityOracle: Address;
  /** AgentVisaRegistry, applications, leaderboard, capability discovery. */
  visaRegistry: Address;
  /** MentoPriceAdapter, prices supported tokens into cUSD. */
  priceAdapter: Address;
}

export const CELO_MAINNET_ID = 42220 as const;

export const CELO_MAINNET: VisaProofContracts = {
  passport: "0x665EB52aE88C0927daB1eF1ff47B030dbB9C6180",
  activityOracle: "0x5eDA6AAB3df76c5A9876C9e6e76321B23f7fE9a4",
  visaRegistry: "0x4Bba05eC290b3AA3C9E7831fBC4A713E3340827F",
  priceAdapter: "0xD6c7DE4E408b157d0284F4D927980b5b302C5880",
};

/** ERC-8004 identity registry VisaProof keys agents on ("AgentIdentity"/"AGENT"). */
export const IDENTITY_REGISTRY: Address = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432";

/** Self Agent ID registry ("Self Agent ID"/"SAID") read for proof of human. */
export const SELF_AGENT_REGISTRY: Address = "0xaC3DF9ABf80d0F5c020C06B04Cced27763355944";

/**
 * Supported activity tokens on Celo mainnet, keyed by symbol. Pass either a
 * symbol from this map or a raw address anywhere the SDK takes a token.
 */
export const TOKENS = {
  cUSD: "0x765DE816845861e75A25fCA122bb6898B8B1282a",
  cEUR: "0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73",
  cREAL: "0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787",
  USDT: "0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e",
  USDC: "0xcebA9300f2b948710d2653dD7B07f33A8B32118C",
} as const satisfies Record<string, Address>;

export type TokenSymbol = keyof typeof TOKENS;

/** Resolve a token symbol or address to a checksum address. */
export function resolveToken(token: TokenSymbol | Address): Address {
  return (TOKENS as Record<string, Address>)[token] ?? (token as Address);
}
