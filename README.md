# VisaProof

On chain activity verification and Visa qualification for AI agents on Celo.

VisaProof lets an agent prove its Celo activity and earn a Visa tier (Tourist,
Work Visa, Citizenship) from verifiable on chain data instead of manual review.
An agent submits the transactions it wants counted, the protocol prices their
volume into cUSD and tallies their count, and the resulting tier is computed
from fixed public thresholds.

## How it works

1. The controller of an ERC 8004 agent identity registers a passport for that
   agent id.
2. The controller submits transaction hashes, amounts and token addresses to
   the activity oracle. Each hash is recorded once globally so the same
   transaction cannot be counted twice, and every amount is converted to a
   cUSD value through the Mento price feed.
3. Anyone can recompute the agent's tier from its verified score. The passport
   only moves up, never down, and only on a genuine threshold crossing.
4. The registry tracks Visa applications, a volume ranked leaderboard, and a
   keyword index so agents can discover high tier counterparts.

Every write is gated by ownership of the agent's ERC 8004 identity NFT, so an
agent's record can only be managed by the address that controls its identity.

## Tiers

A tier is reached by meeting either threshold, transaction count or cUSD volume.

| Tier        | Transactions | Volume (cUSD) |
|-------------|--------------|---------------|
| Tourist     | default      | default       |
| Work Visa   | 1,000        | 5,000         |
| Citizenship | 10,000       | 15,000        |

## Contracts

| Contract | Role |
|----------|------|
| `AgentPassport.sol` | Maps each ERC 8004 agent id to its Visa tier and passport record, and recomputes the tier from verified activity. |
| `AgentActivityOracle.sol` | Records non duplicated transaction hashes, aggregates multi token volume into a single cUSD score per agent. |
| `MentoPriceAdapter.sol` | Prices supported tokens into cUSD. USD pegged stables convert one to one with decimal normalisation, Mento stables route through CELO via the SortedOracles feed. |
| `AgentVisaRegistry.sol` | Visa applications, tier filtered leaderboard, and a keyword index for agent discovery. |

The price adapter sits behind an interface, so the activity oracle does not
depend on any single price source. Bridged USD stables (USDT, USDC) and cUSD
are treated as one to one, while Mento c stables are converted at the live
median rate.

## Supported tokens

cUSD, cEUR, cREAL, USDT and USDC on Celo mainnet. The full set is configurable
by the contract owner.

## Quick start

```bash
forge build
forge test
```

The suite covers the four contracts with their full branch and function set.

## Deployment

`script/Deploy.s.sol` deploys the stack in dependency order and wires the token
configuration. Mainnet addresses live in `script/CeloAddresses.sol` and were
each checked against Celo mainnet.

Dry run against mainnet without broadcasting:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url celo
```

Copy `.env.example` to `.env` and set your RPC URL, deployer key and Celoscan
API key, then add `--broadcast --verify` to deploy.

Because Celo supports CIP 64 fee abstraction, the deploy and every protocol
call can pay gas in cUSD by setting the fee currency at the transaction layer.
No contract change is needed for this.

## Roadmap

* `@visaproof/sdk`, a TypeScript wrapper over the deployed contracts.
* Mainnet deployment and verified source on Celoscan.

## License

MIT
