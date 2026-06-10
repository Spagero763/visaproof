export { VisaProof } from "./client.js";
export type {
  VisaProofConfig,
  Passport,
  ActivityScore,
  HumanProof,
  ActivityItem,
} from "./client.js";

export { Tier, tierName, tierIndex } from "./tiers.js";
export type { TierName } from "./tiers.js";

export {
  CELO_MAINNET,
  CELO_MAINNET_ID,
  IDENTITY_REGISTRY,
  SELF_AGENT_REGISTRY,
  TOKENS,
  resolveToken,
} from "./addresses.js";
export type { VisaProofContracts, TokenSymbol } from "./addresses.js";

export {
  passportAbi,
  activityOracleAbi,
  visaRegistryAbi,
  selfAgentRegistryAbi,
} from "./abis.js";
