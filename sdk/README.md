# @visaproof/sdk

TypeScript SDK for [VisaProof](https://github.com/spagero763/visaproof) — the on-chain
Agent Visa qualification protocol on Celo. Report activity, compute your Visa tier, and
discover high-tier agents in a few lines of code.

It is a thin, typed [viem](https://viem.sh) wrapper over the deployed contracts. Reads
need no signer; pass an `account` to register, submit activity, upgrade tiers, and apply.

## Install

```bash
npm install @visaproof/sdk viem
```

## Quick start

```ts
import { VisaProof } from "@visaproof/sdk";

// Read-only client (no signer needed).
const vp = new VisaProof({ rpcUrl: "https://forno.celo.org", agentId: 9187n });

const { tierName, volumeCUSD, txCount } = await vp.getPassport();
const top = await vp.getLeaderboard({ minTier: "WorkVisa", limit: 10 });
```

```ts
// Signing client: report activity and climb tiers.
const vp = new VisaProof({
  rpcUrl: "https://forno.celo.org",
  account: process.env.AGENT_PRIVATE_KEY as `0x${string}`,
  agentId: 9187n,
});

// One-time: bind the passport to a Self Agent ID proof of human.
await vp.registerAgent({ selfAgentId: 42n });

// After each significant transaction, report it.
await vp.submitActivity({
  txHashes: ["0xabc…", "0xdef…"],
  amounts: [1_000_000n, 2_500000000000000000n], // token native units (USDT 6dp, cUSD 18dp)
  tokens: ["USDT", "cUSD"],
});

// Recompute the tier once thresholds are crossed.
await vp.upgradeTier();
```

`tokens` accepts a symbol (`cUSD`, `cEUR`, `cREAL`, `USDT`, `USDC`) or any address.
Every `agentId` argument is optional when a default is set on the client.

## API

| Method | Kind | Description |
|--------|------|-------------|
| `getPassport(agentId?)` | read | Full passport: tier, volume, tx count, bound Self Agent ID + nullifier |
| `getTier(agentId?)` | read | Current tier and its name |
| `isRegistered(agentId?)` | read | Whether a passport exists |
| `humanProof(agentId?)` | read | Live proof-of-human status for the bound Self Agent ID |
| `previewTier(volume, txCount)` | read | Tier for a hypothetical score |
| `getActivityScore(agentId?)` | read | Aggregated cUSD volume, tx count, last update |
| `supportedTokens()` / `verifiedTokens(agentId?)` | read | Token sets |
| `getLeaderboard({ minTier, limit })` | read | Top agents by volume at or above a tier |
| `isEligible(tier, agentId?)` | read | Whether live score qualifies for a tier |
| `getAgentsByCapability(keyword)` / `capabilitiesOf(agentId?)` | read | Capability discovery |
| `registerAgent({ selfAgentId, agentId? })` | write | Create a passport gated on proof of human |
| `submitActivity({ txHashes, amounts, tokens, agentId? })` | write | Submit transaction proofs |
| `reportActivity({ items, agentId? })` | write | Same, from `{ txHash, amount, token }[]` |
| `upgradeTier(agentId?)` | write | Raise tier from verified activity |
| `applyForVisa(agentId?)` | write | Enter the leaderboard / discovery index |
| `setCapability(keyword, agentId?)` / `removeCapability(...)` | write | Manage discovery keywords |
| `waitForReceipt(hash)` | util | Await a transaction receipt |

Writes return the transaction hash; `await vp.waitForReceipt(hash)` to confirm.

## Addresses

Mainnet contract addresses are bundled (see `CELO_MAINNET`). Override any of them via
the `contracts` option — for example to target a local fork or a new deployment:

```ts
const vp = new VisaProof({ rpcUrl, contracts: { passport: "0x…" } });
```

The bundled addresses are the live proof-of-human v2 stack on Celo mainnet —
`registerAgent(agentId, selfAgentId)` and the 7-field passport struct match the
deployed `AgentPassport`.

## License

MIT
