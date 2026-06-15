import {
  createPublicClient,
  createWalletClient,
  http,
  type Account,
  type Address,
  type Chain,
  type Hash,
  type Hex,
  type PublicClient,
  type TransactionReceipt,
  type WalletClient,
} from "viem";
import { celo } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

import { activityOracleAbi, passportAbi, visaRegistryAbi } from "./abis.js";
import {
  CELO_MAINNET,
  resolveToken,
  type TokenSymbol,
  type VisaProofContracts,
} from "./addresses.js";
import { Tier, tierIndex, tierName, type TierName } from "./tiers.js";

type Numeric = bigint | number | string;

export interface VisaProofConfig {
  /** RPC URL for Celo. Defaults to the chain's public RPC (set one for production). */
  rpcUrl?: string;
  /** Signer for write calls: a 0x private key or a viem `Account`. Omit for read-only. */
  account?: Account | Hex;
  /** Default ERC-8004 agent id, so per-call `agentId` can be omitted. */
  agentId?: Numeric;
  /** Override any deployed contract address (e.g. a v2 passport). */
  contracts?: Partial<VisaProofContracts>;
  /** Override the chain (defaults to Celo mainnet). */
  chain?: Chain;
}

export interface Passport {
  registered: boolean;
  tier: Tier;
  tierName: TierName;
  volumeCUSD: bigint;
  txCount: bigint;
  updatedAt: bigint;
  selfAgentId: bigint;
  humanNullifier: bigint;
}

export interface ActivityScore {
  totalVolumeCUSD: bigint;
  txCount: bigint;
  lastUpdated: bigint;
}

export interface HumanProof {
  selfAgentId: bigint;
  nullifier: bigint;
  /** Whether the bound Self Agent ID still carries a fresh proof right now. */
  human: boolean;
}

export interface ActivityItem {
  txHash: Hex;
  amount: Numeric;
  token: TokenSymbol | Address;
}

function toBigInt(v: Numeric): bigint {
  return typeof v === "bigint" ? v : BigInt(v);
}

/**
 * VisaProof, a thin, typed wrapper over the on-chain Agent Visa qualification
 * protocol on Celo. Read tier/activity with no signer; pass an `account` to
 * register, submit activity, upgrade tiers and apply for a visa.
 *
 * ```ts
 * const vp = new VisaProof({ rpcUrl, account: PRIVATE_KEY, agentId: 1234n });
 * await vp.registerAgent({ selfAgentId: 42n });
 * await vp.submitActivity({ txHashes, amounts, tokens: ["cUSD", "USDT"] });
 * const { tierName, volumeCUSD } = await vp.getPassport();
 * const top = await vp.getLeaderboard({ minTier: "WorkVisa", limit: 10 });
 * ```
 */
export class VisaProof {
  readonly chain: Chain;
  readonly contracts: VisaProofContracts;
  readonly public: PublicClient;
  readonly wallet?: WalletClient;
  readonly account?: Account;

  private readonly defaultAgentId?: bigint;

  constructor(config: VisaProofConfig = {}) {
    this.chain = config.chain ?? celo;
    const transport = http(config.rpcUrl);
    this.public = createPublicClient({ chain: this.chain, transport });
    this.contracts = { ...CELO_MAINNET, ...config.contracts };
    this.defaultAgentId = config.agentId === undefined ? undefined : toBigInt(config.agentId);

    if (config.account) {
      this.account =
        typeof config.account === "string" ? privateKeyToAccount(config.account) : config.account;
      this.wallet = createWalletClient({
        account: this.account,
        chain: this.chain,
        transport,
      });
    }
  }

  // -------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------

  /** Full passport record for an agent (decoded, with the tier name). */
  async getPassport(agentId?: Numeric): Promise<Passport> {
    const p = await this.public.readContract({
      address: this.contracts.passport,
      abi: passportAbi,
      functionName: "getPassport",
      args: [this.agent(agentId)],
    });
    return {
      registered: p.registered,
      tier: p.tier as Tier,
      tierName: tierName(p.tier),
      volumeCUSD: p.volumeCUSD,
      txCount: p.txCount,
      updatedAt: p.updatedAt,
      selfAgentId: p.selfAgentId,
      humanNullifier: p.humanNullifier,
    };
  }

  /** Current tier of an agent. */
  async getTier(agentId?: Numeric): Promise<{ tier: Tier; name: TierName }> {
    const tier = await this.public.readContract({
      address: this.contracts.passport,
      abi: passportAbi,
      functionName: "getTier",
      args: [this.agent(agentId)],
    });
    return { tier: tier as Tier, name: tierName(tier) };
  }

  /** Whether an agent holds a VisaProof passport. */
  isRegistered(agentId?: Numeric): Promise<boolean> {
    return this.public.readContract({
      address: this.contracts.passport,
      abi: passportAbi,
      functionName: "isRegistered",
      args: [this.agent(agentId)],
    });
  }

  /** Live proof-of-human status for a registered agent. */
  async humanProof(agentId?: Numeric): Promise<HumanProof> {
    const [selfAgentId, nullifier, human] = await this.public.readContract({
      address: this.contracts.passport,
      abi: passportAbi,
      functionName: "humanProof",
      args: [this.agent(agentId)],
    });
    return { selfAgentId, nullifier, human };
  }

  /** Tier an agent would reach at the given volume and tx count, without writing. */
  async previewTier(volumeCUSD: Numeric, txCount: Numeric): Promise<{ tier: Tier; name: TierName }> {
    const tier = await this.public.readContract({
      address: this.contracts.passport,
      abi: passportAbi,
      functionName: "previewTier",
      args: [toBigInt(volumeCUSD), toBigInt(txCount)],
    });
    return { tier: tier as Tier, name: tierName(tier) };
  }

  /** Aggregated activity score (cUSD volume, tx count, last update) for an agent. */
  async getActivityScore(agentId?: Numeric): Promise<ActivityScore> {
    const [totalVolumeCUSD, txCount, lastUpdated] = await this.public.readContract({
      address: this.contracts.activityOracle,
      abi: activityOracleAbi,
      functionName: "getActivityScore",
      args: [this.agent(agentId)],
    });
    return { totalVolumeCUSD, txCount, lastUpdated };
  }

  /** Tokens supported for activity submission, as addresses. */
  supportedTokens(): Promise<readonly Address[]> {
    return this.public.readContract({
      address: this.contracts.activityOracle,
      abi: activityOracleAbi,
      functionName: "supportedTokens",
    });
  }

  /** Tokens an agent has submitted activity in. */
  verifiedTokens(agentId?: Numeric): Promise<readonly Address[]> {
    return this.public.readContract({
      address: this.contracts.activityOracle,
      abi: activityOracleAbi,
      functionName: "verifiedTokens",
      args: [this.agent(agentId)],
    });
  }

  /** Top applicants at or above `minTier`, sorted by volume, truncated to `limit`. */
  getLeaderboard(opts: { minTier: TierName | Tier | number; limit: Numeric }): Promise<readonly bigint[]> {
    return this.public.readContract({
      address: this.contracts.visaRegistry,
      abi: visaRegistryAbi,
      functionName: "getLeaderboard",
      args: [tierIndex(opts.minTier), toBigInt(opts.limit)],
    });
  }

  /** Whether an agent's live oracle score qualifies for `tier`. */
  isEligible(tier: TierName | Tier | number, agentId?: Numeric): Promise<boolean> {
    return this.public.readContract({
      address: this.contracts.visaRegistry,
      abi: visaRegistryAbi,
      functionName: "isEligible",
      args: [this.agent(agentId), tierIndex(tier)],
    });
  }

  /** Agents indexed under a capability keyword (case sensitive). */
  getAgentsByCapability(capability: string): Promise<readonly bigint[]> {
    return this.public.readContract({
      address: this.contracts.visaRegistry,
      abi: visaRegistryAbi,
      functionName: "getAgentsByCapability",
      args: [capability],
    });
  }

  /** Capability keywords declared by an agent. */
  capabilitiesOf(agentId?: Numeric): Promise<readonly string[]> {
    return this.public.readContract({
      address: this.contracts.visaRegistry,
      abi: visaRegistryAbi,
      functionName: "capabilitiesOf",
      args: [this.agent(agentId)],
    });
  }

  // -------------------------------------------------------------------
  // Writes (require an account)
  // -------------------------------------------------------------------

  /** Register a passport, binding it to a Self Agent ID proof of human. */
  registerAgent(opts: { selfAgentId: Numeric; agentId?: Numeric }): Promise<Hash> {
    return this.write(this.contracts.passport, passportAbi, "registerAgent", [
      this.agent(opts.agentId),
      toBigInt(opts.selfAgentId),
    ]);
  }

  /** Submit proof of transactions. Arrays must be equal length and aligned. */
  submitActivity(opts: {
    txHashes: Hex[];
    amounts: Numeric[];
    tokens: (TokenSymbol | Address)[];
    agentId?: Numeric;
  }): Promise<Hash> {
    const { txHashes, amounts, tokens } = opts;
    if (txHashes.length !== amounts.length || txHashes.length !== tokens.length) {
      throw new Error("submitActivity: txHashes, amounts and tokens must be the same length");
    }
    if (txHashes.length === 0) throw new Error("submitActivity: empty submission");
    return this.write(this.contracts.activityOracle, activityOracleAbi, "submitActivity", [
      this.agent(opts.agentId),
      txHashes,
      amounts.map(toBigInt),
      tokens.map(resolveToken),
    ]);
  }

  /** Ergonomic activity submission from a list of `{ txHash, amount, token }`. */
  reportActivity(opts: { items: ActivityItem[]; agentId?: Numeric }): Promise<Hash> {
    return this.submitActivity({
      agentId: opts.agentId,
      txHashes: opts.items.map((i) => i.txHash),
      amounts: opts.items.map((i) => i.amount),
      tokens: opts.items.map((i) => i.token),
    });
  }

  /** Recompute and raise an agent's tier from its verified activity. */
  upgradeTier(agentId?: Numeric): Promise<Hash> {
    return this.write(this.contracts.passport, passportAbi, "upgradeTier", [this.agent(agentId)]);
  }

  /** Submit an agent for Visa consideration (requires an existing passport). */
  applyForVisa(agentId?: Numeric): Promise<Hash> {
    return this.write(this.contracts.visaRegistry, visaRegistryAbi, "applyForVisa", [
      this.agent(agentId),
    ]);
  }

  /** Add a capability keyword to an agent's discovery index. */
  setCapability(capability: string, agentId?: Numeric): Promise<Hash> {
    return this.write(this.contracts.visaRegistry, visaRegistryAbi, "setCapability", [
      this.agent(agentId),
      capability,
    ]);
  }

  /** Remove a previously declared capability from an agent. */
  removeCapability(capability: string, agentId?: Numeric): Promise<Hash> {
    return this.write(this.contracts.visaRegistry, visaRegistryAbi, "removeCapability", [
      this.agent(agentId),
      capability,
    ]);
  }

  /** Wait for a transaction to be mined and return its receipt. */
  waitForReceipt(hash: Hash): Promise<TransactionReceipt> {
    return this.public.waitForTransactionReceipt({ hash });
  }

  // -------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------

  private agent(agentId?: Numeric): bigint {
    if (agentId !== undefined) return toBigInt(agentId);
    if (this.defaultAgentId !== undefined) return this.defaultAgentId;
    throw new Error("No agentId provided and no default agentId set on the client");
  }

  private write(
    address: Address,
    abi: typeof passportAbi | typeof activityOracleAbi | typeof visaRegistryAbi,
    functionName: string,
    args: readonly unknown[],
  ): Promise<Hash> {
    if (!this.wallet || !this.account) {
      throw new Error("This call needs a signer, construct VisaProof with an `account`");
    }
    return this.wallet.writeContract({
      address,
      abi: abi as never,
      functionName: functionName as never,
      args: args as never,
      account: this.account,
      chain: this.chain,
    });
  }
}
