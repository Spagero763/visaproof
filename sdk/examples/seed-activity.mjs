// VisaProof — honest activity seeder.
//
// Exercises the live protocol end to end with REAL on-chain transactions:
// registers a passport (gated on your Self Agent ID), makes real cUSD
// transfers, submits those real tx hashes to the activity oracle, applies for
// a visa, declares a capability, and reads everything back. Every call is a
// genuine mainnet transaction a reviewer can click on Celoscan — no synthetic
// hashes, no wash trading.
//
// Runs each transaction sequentially (waits for every receipt before the next)
// so it is safe for an EIP-7702 delegated deployer on Celo's sequencer.
//
// Usage (from the sdk/ directory, after `npm run build`):
//   export PRIVATE_KEY=0x...        # your deployer key, LOCAL ONLY — never commit
//   export CELO_RPC_URL=https://forno.celo.org
//   export TRANSFERS=25             # how many real transfers to make (optional)
//   node examples/seed-activity.mjs
//
// Recover the key from your keystore once with:
//   cast wallet private-key --account visaproof-deployer
// and `unset PRIVATE_KEY` when you are done.

import { createPublicClient, createWalletClient, http, parseAbi, parseUnits, formatUnits } from "viem";
import { celo } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { VisaProof, TOKENS, tierName } from "../dist/index.js";

const RPC = process.env.CELO_RPC_URL || "https://forno.celo.org";
const PK = process.env.PRIVATE_KEY;
const AGENT_ID = BigInt(process.env.AGENT_ID || "9187");
const SELF_ID = BigInt(process.env.SELF_AGENT_ID || "140");
const TRANSFERS = Number(process.env.TRANSFERS || "25");
const AMOUNT = process.env.AMOUNT || "0.001"; // cUSD per transfer
const CAPABILITY = process.env.CAPABILITY || "visa-qualification";
// Optional: real counterparties to receive the transfers (comma-separated).
// Defaults to a self-transfer when unset.
const RECIPIENTS = (process.env.RECIPIENTS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

if (!PK) {
  console.error("Set PRIVATE_KEY (0x...) in your environment. Run locally only; never commit it.");
  process.exit(1);
}

const account = privateKeyToAccount(PK);
const transport = http(RPC);
const pub = createPublicClient({ chain: celo, transport });
const wallet = createWalletClient({ account, chain: celo, transport });
const vp = new VisaProof({ rpcUrl: RPC, account, agentId: AGENT_ID });

const erc20 = parseAbi(["function transfer(address to, uint256 amount) returns (bool)"]);
const amount = parseUnits(AMOUNT, 18);
const txLog = [];

async function step(label, fn) {
  try {
    const hash = await fn();
    if (hash) {
      await pub.waitForTransactionReceipt({ hash });
      txLog.push(hash);
      console.log(`  ok  ${label}  ${hash}`);
    } else {
      console.log(`  --  ${label} (skipped)`);
    }
    return hash;
  } catch (err) {
    console.log(`  !!  ${label} — ${err.shortMessage || err.message}`);
    return undefined;
  }
}

async function main() {
  console.log(`VisaProof activity seeder`);
  console.log(`  signer    ${account.address}`);
  console.log(`  agent     ${AGENT_ID}   selfAgentId ${SELF_ID}`);
  console.log(`  transfers ${TRANSFERS} x ${AMOUNT} cUSD\n`);

  // 1. Register the passport (gated on a fresh Self Agent ID proof of human).
  if (await vp.isRegistered()) {
    console.log(`  --  passport already registered for ${AGENT_ID}`);
  } else {
    await step("registerAgent", () => vp.registerAgent({ selfAgentId: SELF_ID }));
  }

  // 2. Make real cUSD transfers and collect their hashes as activity proofs.
  const items = [];
  for (let i = 0; i < TRANSFERS; i++) {
    const to = RECIPIENTS.length ? RECIPIENTS[i % RECIPIENTS.length] : account.address;
    const hash = await step(`transfer ${i + 1}/${TRANSFERS} -> ${to.slice(0, 8)}…`, () =>
      wallet.writeContract({
        address: TOKENS.cUSD,
        abi: erc20,
        functionName: "transfer",
        args: [to, amount], // real cUSD transfer to a counterparty (or self when none set)
        account,
        chain: celo,
      }),
    );
    if (hash) items.push({ txHash: hash, amount, token: "cUSD" });
  }

  // 3. Submit those real hashes to the oracle (batched to keep gas sane).
  for (let i = 0; i < items.length; i += 20) {
    const batch = items.slice(i, i + 20);
    await step(`submitActivity (${batch.length} hashes)`, () =>
      vp.submitActivity({
        txHashes: batch.map((b) => b.txHash),
        amounts: batch.map((b) => b.amount),
        tokens: batch.map(() => "cUSD"),
      }),
    );
  }

  // 4. Enter the leaderboard / discovery index.
  await step("applyForVisa", () => vp.applyForVisa());
  await step(`setCapability "${CAPABILITY}"`, () => vp.setCapability(CAPABILITY));

  // 5. Read the resulting state.
  const passport = await vp.getPassport();
  const score = await vp.getActivityScore();
  const preview = await vp.previewTier(passport.volumeCUSD, passport.txCount);
  const board = await vp.getLeaderboard({ minTier: "Tourist", limit: 10 });

  console.log(`\nResult for agent ${AGENT_ID}:`);
  console.log(`  tier (on-chain) : ${passport.tierName}`);
  console.log(`  volume (cUSD)   : ${formatUnits(score.totalVolumeCUSD, 18)}`);
  console.log(`  tx count        : ${score.txCount}`);
  console.log(`  bound human     : selfAgentId ${passport.selfAgentId}, nullifier ${passport.humanNullifier}`);
  console.log(`  tier at score   : ${tierName(preview.tier)} (computed by previewTier)`);
  console.log(`  leaderboard     : [${board.join(", ")}]`);

  console.log(`\n${txLog.length} mainnet transactions sent. Hashes for the application:`);
  txLog.forEach((h) => console.log(`  https://celoscan.io/tx/${h}`));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
