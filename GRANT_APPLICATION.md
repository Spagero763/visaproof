# VisaProof, Prezenti Frontier Pool application

Paste-ready answers. Fill the `<...>` placeholders (X handle, KYC).

---

### Product name
VisaProof

### Team Name
spagero763

### Website
https://visaproof.vercel.app

### X Handle
<your X handle>

### KarmaGAP profile
https://www.karmahq.xyz/project/visaproof

### Github
https://github.com/Spagero763/visaproof

### ERC-8004 registration
Yes. Agent id 9187 in the Celo mainnet Identity Registry
`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`
(https://celoscan.io/token/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432?a=9187).
Registered even though AI infrastructure is exempt.

### Is your project fully open source
Yes. https://github.com/Spagero763/visaproof, MIT. Four contracts verified on
Celoscan and an SDK on npm (`npm install visaproof-sdk`).

### Deployed on Celo mainnet
Yes, all four contracts deployed and verified (chain 42220):
- AgentPassport: https://celoscan.io/address/0x665EB52aE88C0927daB1eF1ff47B030dbB9C6180#code
- AgentActivityOracle: https://celoscan.io/address/0x5eDA6AAB3df76c5A9876C9e6e76321B23f7fE9a4#code
- AgentVisaRegistry: https://celoscan.io/address/0x4Bba05eC290b3AA3C9E7831fBC4A713E3340827F#code
- MentoPriceAdapter: https://celoscan.io/address/0xD6c7DE4E408b157d0284F4D927980b5b302C5880#code

### Self Agent ID
Yes. Self Agent ID 140, held by
`0x32a3596C25A98950E850E3531a0aA87f1506e5d7` in the Self registry
`0xaC3DF9ABf80d0F5c020C06B04Cced27763355944`, with a fresh proof of human. You
cannot open a VisaProof passport without holding a Self Agent ID like this one.

### Describe your project
VisaProof works out whether an AI agent qualifies for Celo's Agent Visa, and
proves it on-chain. An agent reports the transactions it wants counted. The
protocol checks each one, adds up the volume across Mento stablecoins in cUSD,
counts how many there were, and decides the tier (Tourist, Work Visa, or
Citizenship) against fixed public numbers. Nobody reviews it by hand.

The part that makes the score worth anything: you can only open a passport if you
hold a Self Agent ID, which proves a real human is behind the agent. Tier and
activity go to a public leaderboard so other agents can find you. There are four
contracts, all verified on Celo mainnet, an SDK so any framework can plug in
(visaproof-sdk), and a live explorer at visaproof.vercel.app. Gas can be paid in
cUSD.

### Infrastructure focus
This is something other builders use, not an app for end users. If you run an
agent on Celo and you want the Agent Visa (which unlocks liquidity and MiniPay),
you have to show your activity on-chain somewhere. VisaProof is where that
happens.

The piece that matters is the human gate. A passport only exists if a verified
human controls it. The Self registry limits how many agents one human can hold
and ties each to a nullifier, so the activity behind a tier is always a real
person's. Take this layer away and Visa qualification goes back to people
reporting their own numbers and hoping nobody faked them.

### Verifiable onchain activity (demo)
All of it is on Celoscan. So far, 30 transactions from one verified human.
- Agent 9187 opened a passport gated on Self Agent ID 140:
  `0x083bf2011d1fba94b304b4b9b3e9484a87062af2f3116c1a4951d5462ef56c55`
- 25 pieces of real activity submitted, adding up to 0.025 cUSD:
  `0x04f2ca190e83f9637a3cff2ee84376e3f8d382e7bdebb975bbbb3f80e6275431`
- Applied for a visa (now on the leaderboard):
  `0x6d4623340d2516db7bf070ae49dd86ee9e8d7223da4f63cd47d5908aa3c4ba6a`
- Set a capability for discovery:
  `0x54a8027bc7174ffc1e231c217ee62f0d84c431b1319a037fdfcca9093870f28f`

The leaderboard and the capability search both return agent 9187. This is a
seeded demo from one operator, not pretend adoption, and it cannot be inflated
because the Self gate caps registrations by human. Live demo:
visaproof.vercel.app. Video: <your YouTube link>

### How do you plan on getting agents to use your product? Activation path for first 10 to 100 users
The demand is already there. Agents that want a higher Visa tier have to prove
their activity somewhere, and right now there is nowhere good to do it. That is
the hook, not something I have to sell.

The SDK makes reporting activity a few lines of code. Once an agent has a tier it
shows up on the leaderboard, which is where other agents look for partners, so
usage brings in more usage. The first agents to reach are the ones already
registered in Self Agent ID and ERC-8004 on Celo, since they are the ones chasing
Visa status. I will reach them through the Agent Visa program, 8004scan, and the
Celo builder channels.

### Distribution strategy and examples from this or prior work
Distribution runs on rails agents already touch: the npm package, the ERC-8004
reputation registry so agents appear on 8004scan, and the Visa program itself as
the reason to use it. I will be straight about where this stands: the contracts
and SDK are live, but nobody outside the project is using it yet. This is the
first push. What I can point to from before is the on-chain payment and CIP-64
work the Celo team complimented in my last review, which shows I can ship a real
Celo integration end to end.

### Who have you worked with before in the Celo ecosystem?
<select honestly, see note below; likely "None of the above">

### Clear contribution to the ecosystem
Today, qualifying for the Agent Visa is manual and the activity behind it is not
checked. VisaProof makes it automatic and verifiable, and ties every tier to a
real person so it cannot be gamed. That gives the Foundation a qualification
layer that runs itself and that nobody can farm, which is the difference between
rewarding real agent activity and rewarding whoever spins up the most bots.

### Technical credibility
Four contracts live and verified on mainnet, 107 Foundry tests, an SDK on npm, an
MIT repo, and a working explorer. For proof of human I read the live Self Agent
ID registry instead of writing my own zero-knowledge code, so I consume Self's
verified result rather than reinventing it. Volume across stablecoins goes
through the Mento oracle, and tiers come from fixed public thresholds. This
builds on the CIP-64 payment work the Celo team complimented before.

### Tech category
Verification and trust infrastructure (also covers agent identity and discovery).

---

## KYC and delivery, fill these directly on the form (not here, not in git)
- Grant policies: agree
- Name of lead applicant (KYC): <your legal name>
- Email of lead applicant: <your email>
- Country of registration: <your country>
- Your logo: upload web/public/logo.png (or visaproof.vercel.app/logo.png)
- Grant L2 delivery address: <a Celo address you control>
