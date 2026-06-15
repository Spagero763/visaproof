import { parseAbi } from "viem";

/** AgentPassport, the subset of functions the SDK calls. */
export const passportAbi = parseAbi([
  "function registerAgent(uint256 agentId, uint256 selfAgentId)",
  "function upgradeTier(uint256 agentId)",
  "function getTier(uint256 agentId) view returns (uint8)",
  "function isRegistered(uint256 agentId) view returns (bool)",
  "function previewTier(uint256 volumeCUSD, uint256 txCount) view returns (uint8)",
  "function humanProof(uint256 agentId) view returns (uint256 selfAgentId, uint256 nullifier, bool human)",
  "function getPassport(uint256 agentId) view returns ((bool registered, uint8 tier, uint256 volumeCUSD, uint256 txCount, uint256 updatedAt, uint256 selfAgentId, uint256 humanNullifier))",
  "function WORK_VISA_TX_COUNT() view returns (uint256)",
  "function WORK_VISA_VOLUME_CUSD() view returns (uint256)",
  "function CITIZENSHIP_TX_COUNT() view returns (uint256)",
  "function CITIZENSHIP_VOLUME_CUSD() view returns (uint256)",
]);

/** AgentActivityOracle, submission and score reads. */
export const activityOracleAbi = parseAbi([
  "function submitActivity(uint256 agentId, bytes32[] txHashes, uint256[] amounts, address[] tokens)",
  "function getActivityScore(uint256 agentId) view returns (uint256 totalVolumeCUSD, uint256 txCount, uint256 lastUpdated)",
  "function aggregateVolume(uint256 agentId) view returns (uint256)",
  "function verifiedTokens(uint256 agentId) view returns (address[])",
  "function supportedTokens() view returns (address[])",
]);

/** AgentVisaRegistry, applications, leaderboard, capability discovery. */
export const visaRegistryAbi = parseAbi([
  "function applyForVisa(uint256 agentId)",
  "function setCapability(uint256 agentId, string capability)",
  "function removeCapability(uint256 agentId, string capability)",
  "function isEligible(uint256 agentId, uint8 tier) view returns (bool)",
  "function getLeaderboard(uint8 minTier, uint256 limit) view returns (uint256[])",
  "function getAgentsByCapability(string capability) view returns (uint256[])",
  "function capabilitiesOf(uint256 agentId) view returns (string[])",
  "function applicantsCount() view returns (uint256)",
  "function applicants() view returns (uint256[])",
]);

/** Self Agent ID registry, proof-of-human reads. */
export const selfAgentRegistryAbi = parseAbi([
  "function ownerOf(uint256 selfAgentId) view returns (address)",
  "function hasHumanProof(uint256 selfAgentId) view returns (bool)",
  "function isProofFresh(uint256 selfAgentId) view returns (bool)",
  "function getHumanNullifier(uint256 selfAgentId) view returns (uint256)",
]);
