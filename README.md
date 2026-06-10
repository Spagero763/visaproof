# VisaProof

On chain activity verification and Visa qualification for AI agents on Celo.

VisaProof lets an agent prove its Celo activity and earn a Visa tier (Tourist,
Work Visa, Citizenship) from verifiable on chain data instead of manual review.
An agent submits the transactions it wants counted, the protocol prices their
volume into cUSD and tallies their count, and the resulting tier is computed
from fixed public thresholds.

## How it works

1. The controller of an ERC 8004 agent identity registers a passport for that
   agent id, presenting a Self Agent ID they also control. The passport is
   bound to that Self Agent ID's human nullifier, so every VisaProof identity
   traces back to a verified human (see [Proof of human](#proof-of-human)).
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

## Proof of human

Passport registration is Sybil resistant. To register, the controller must also
own a [Self Agent ID](https://selfagentid.xyz) — a soulbound identity backed by a
Self Protocol zero knowledge passport proof — that carries a fresh proof of human.
`AgentPassport` reads the Self Agent ID registry on Celo mainnet and requires:

* the caller owns the supplied Self Agent ID,
* it has a human proof that is currently fresh (proofs expire and can be revoked),

then records that human's nullifier on the passport. Self performs all zero
knowledge verification; VisaProof only consumes the on-chain result, so no proof
plumbing lives in the protocol. `humanProof(agentId)` re-reads the live status at
any time. One human may control passports for several agents, but every passport
is anchored to a real, verified person.

| Field | Value |
|-------|-------|
| Self Agent ID registry | [`0xaC3DF9ABf80d0F5c020C06B04Cced27763355944`](https://celoscan.io/address/0xaC3DF9ABf80d0F5c020C06B04Cced27763355944) (symbol `SAID`) |

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
| `AgentPassport.sol` | Maps each ERC 8004 agent id to its Visa tier and passport record, gates registration on a Self Agent ID proof of human, and recomputes the tier from verified activity. |
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

## Deployments

Live on Celo mainnet (chain id 42220), all four contracts verified on Celoscan.

| Contract | Address |
|----------|---------|
| `MentoPriceAdapter` | [`0xD6c7DE4E408b157d0284F4D927980b5b302C5880`](https://celoscan.io/address/0xD6c7DE4E408b157d0284F4D927980b5b302C5880#code) |
| `AgentActivityOracle` | [`0x5eDA6AAB3df76c5A9876C9e6e76321B23f7fE9a4`](https://celoscan.io/address/0x5eDA6AAB3df76c5A9876C9e6e76321B23f7fE9a4#code) |
| `AgentPassport` | [`0x665EB52aE88C0927daB1eF1ff47B030dbB9C6180`](https://celoscan.io/address/0x665EB52aE88C0927daB1eF1ff47B030dbB9C6180#code) |
| `AgentVisaRegistry` | [`0x4Bba05eC290b3AA3C9E7831fBC4A713E3340827F`](https://celoscan.io/address/0x4Bba05eC290b3AA3C9E7831fBC4A713E3340827F#code) |

`AgentPassport` here is the proof-of-human v2: registration is gated on a
[Self Agent ID](#proof-of-human). An earlier pre-gate stack was deployed at
different addresses and is superseded by the contracts above.

## Identity

VisaProof is registered as an [ERC 8004 agent identity](https://eips.ethereum.org/EIPS/eip-8004)
on Celo mainnet.

| Field | Value |
|-------|-------|
| Registry | [`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`](https://celoscan.io/token/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432?a=9187) |
| Agent id | `9187` |
| Agent URI | [`ipfs://bafkreid6ht2mvp2rq7t7ujtpodnoymekyfxtdxgzicpohwdpjusszltlha`](https://gateway.pinata.cloud/ipfs/bafkreid6ht2mvp2rq7t7ujtpodnoymekyfxtdxgzicpohwdpjusszltlha) |

The registration JSON in `registration.json` lists each VisaProof contract as
an entry in the agent's services array, so off chain indexers can discover the
full stack from a single identity.

## Local development

```bash
forge build
forge test
```

The suite covers the four contracts with their full branch and function set.

## Redeploying

`script/Deploy.s.sol` deploys the stack in dependency order and wires the
token configuration. Mainnet addresses live in `script/CeloAddresses.sol` and
were each checked against Celo mainnet.

Dry run against mainnet without broadcasting:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url celo \
  --sender 0xYourDeployerAddress
```

Copy `.env.example` to `.env` and set your RPC URL and Celoscan API key.
Import your deployer key into an encrypted keystore once with
`cast wallet import visaproof-deployer --interactive`, then deploy:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url celo \
  --account visaproof-deployer --sender 0xYourDeployerAddress \
  --broadcast --verify
```

`--sender` must match the keystore address: the script captures `msg.sender`
to set the protocol owner, and the subsequent admin calls broadcast from the
same address.

Because Celo supports CIP 64 fee abstraction, the deploy and every protocol
call can pay gas in cUSD by setting the fee currency at the transaction layer.
No contract change is needed for this.

## TypeScript SDK

[`@visaproof/sdk`](sdk/) is a typed [viem](https://viem.sh) wrapper over the
deployed contracts. Reads need no signer; pass an `account` to register, submit
activity, upgrade tiers and apply.

```ts
import { VisaProof } from "@visaproof/sdk";

const vp = new VisaProof({ rpcUrl, account: AGENT_KEY, agentId: 9187n });

await vp.registerAgent({ selfAgentId: 42n });
await vp.submitActivity({ txHashes, amounts, tokens: ["cUSD", "USDT"] });
const { tierName, volumeCUSD } = await vp.getPassport();
const top = await vp.getLeaderboard({ minTier: "WorkVisa", limit: 10 });
```

See [sdk/README.md](sdk/README.md) for the full API. Build it with
`cd sdk && npm install && npm run build`.

## License

MIT
