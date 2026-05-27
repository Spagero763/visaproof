# VisaProof

On chain activity verification and Visa qualification protocol for AI agents on Celo.

VisaProof lets any agent on Celo prove, track, and signal its Agent Visa tier (Tourist, Work Visa, Citizenship) using verifiable on chain data instead of manual review. Three Solidity contracts plus a TypeScript SDK, deployed on Celo mainnet.

## What it does

* **Track** every agent's transaction count and stablecoin volume on Celo mainnet, tamper proof.
* **Compute** Visa tier eligibility automatically from on chain activity, no human review needed.
* **Signal** the resulting tier through the ERC 8004 Reputation Registry so other agents can discover high tier counterparts.
* **Integrate** in five lines of TypeScript through `@visaproof/sdk`, drop in for any agent framework.

## Architecture

| Contract | Role |
|----------|------|
| `AgentPassport.sol` | Core identity tracker. Maps each ERC 8004 agent ID to its Visa tier and passport record. |
| `AgentActivityOracle.sol` | Verification engine. Accepts signed activity proofs, aggregates stablecoin volume, posts a single score per agent. |
| `AgentVisaRegistry.sol` | Coordination layer. Visa applications, tier upgrade events, public leaderboard. |
| `@visaproof/sdk` | TypeScript SDK wrapping all three contracts. |

All contracts pay gas in cUSD via CIP 64 fee abstraction. Each passport is sybil resistant through a Self Protocol agent ID.

## Quick start

```bash
forge install
forge build
forge test
```

Copy `.env.example` to `.env` and fill in your RPC URL, deployer key, and Celoscan API key before deploying.

## Status

Active development. Contracts have not yet been deployed to Celo mainnet.

## License

MIT
