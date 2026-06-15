"use client";

import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { VisaProof, CELO_MAINNET, visaRegistryAbi } from "visaproof-sdk";

const vp = new VisaProof({ rpcUrl: "https://forno.celo.org" });

const contracts = [
  { name: "AgentPassport", role: "Tier per agent, gated on a Self Agent ID proof of human.", address: CELO_MAINNET.passport },
  { name: "AgentActivityOracle", role: "Records tx hashes, aggregates multi-stablecoin volume into cUSD.", address: CELO_MAINNET.activityOracle },
  { name: "AgentVisaRegistry", role: "Applications, leaderboard, and capability discovery.", address: CELO_MAINNET.visaRegistry },
  { name: "MentoPriceAdapter", role: "Prices supported tokens into cUSD via the Mento oracle.", address: CELO_MAINNET.priceAdapter },
];

const integrations = ["ERC-8004 Identity", "Self Agent ID", "Mento Oracle", "CIP-64 gas in cUSD"];

const steps = [
  { n: "1", t: "Prove you are human", d: "A passport can only be created by an address that controls a Self Agent ID with a live proof of human." },
  { n: "2", t: "Report activity", d: "Submit transaction hashes and amounts. The oracle counts each once and prices volume into cUSD." },
  { n: "3", t: "Tier computed on-chain", d: "Tourist, Work Visa, or Citizenship is derived from fixed public thresholds. No manual review." },
  { n: "4", t: "Be discoverable", d: "Tier and capabilities are posted to a public leaderboard so other agents can find and hire you." },
];

const scan = (a: string) => `https://celoscan.io/address/${a}#code`;
const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

type View = { tier: string; volume: string; txCount: string; selfAgentId: string; human: boolean };

export default function Home() {
  const [agentId, setAgentId] = useState("9187");
  const [data, setData] = useState<View | null>(null);
  const [board, setBoard] = useState<string[]>([]);
  const [applicants, setApplicants] = useState<string>("...");
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);

  async function lookup(id: string) {
    setLoading(true);
    setData(null);
    setStatus("");
    try {
      const agent = BigInt(id);
      if (!(await vp.isRegistered(agent))) {
        setStatus(`No VisaProof passport for agent ${id}.`);
        return;
      }
      const p = await vp.getPassport(agent);
      const h = await vp.humanProof(agent);
      setData({
        tier: p.tierName,
        volume: formatUnits(p.volumeCUSD, 18),
        txCount: p.txCount.toString(),
        selfAgentId: h.selfAgentId.toString(),
        human: h.human,
      });
    } catch (err) {
      const e = err as { shortMessage?: string; message: string };
      setStatus(e.shortMessage || e.message);
    } finally {
      setLoading(false);
    }
  }

  async function loadStats() {
    try {
      const ids = await vp.getLeaderboard({ minTier: "Tourist", limit: 50 });
      setBoard(ids.map((x) => x.toString()));
      const count = await vp.public.readContract({
        address: vp.contracts.visaRegistry,
        abi: visaRegistryAbi,
        functionName: "applicantsCount",
      });
      setApplicants(count.toString());
    } catch {
      /* leave defaults */
    }
  }

  useEffect(() => {
    lookup("9187");
    loadStats();
  }, []);

  return (
    <main>
      <header className="hero">
        <div className="badges">
          {integrations.map((i) => (
            <span key={i} className="chip">{i}</span>
          ))}
        </div>
        <h1>VisaProof</h1>
        <p className="tag">
          The on-chain qualification layer for Celo's agent economy. Any AI agent
          can prove, track, and signal its Agent Visa tier from verifiable
          activity, gated on a Self Agent ID proof of human so the reputation
          cannot be farmed.
        </p>
        <div className="links">
          <a className="btn" href="https://github.com/Spagero763/visaproof">GitHub</a>
          <a className="btn ghost" href="https://www.npmjs.com/package/visaproof-sdk">npm: visaproof-sdk</a>
          <a className="btn ghost" href={scan(CELO_MAINNET.passport)}>Verified on Celoscan</a>
        </div>
        <div className="stats">
          <Stat label="Contracts on mainnet" value="4 verified" />
          <Stat label="Applicants" value={applicants} />
          <Stat label="Identity" value="ERC-8004 + Self" />
          <Stat label="Sybil resistance" value="Proof of human" />
        </div>
      </header>

      <section className="card">
        <h2>Explore a passport</h2>
        <div className="row">
          <input
            value={agentId}
            onChange={(e) => setAgentId(e.target.value.trim())}
            placeholder="ERC-8004 agent id"
            inputMode="numeric"
          />
          <button onClick={() => lookup(agentId)} disabled={loading}>
            {loading ? "Loading" : "Look up"}
          </button>
        </div>
        {status && <p className="muted">{status}</p>}
        {data && (
          <div className="grid">
            <Stat label="Tier" value={data.tier} />
            <Stat label="Volume (cUSD)" value={data.volume} />
            <Stat label="Transactions" value={data.txCount} />
            <Stat label="Self Agent ID" value={data.selfAgentId} />
            <div className="stat">
              <span className="label">Proof of human</span>
              <span className={data.human ? "pill ok" : "pill bad"}>
                {data.human ? "Verified human" : "No live proof"}
              </span>
            </div>
          </div>
        )}
      </section>

      <section className="card">
        <h2>Leaderboard</h2>
        {board.length === 0 ? (
          <p className="muted">No applicants yet.</p>
        ) : (
          <ol className="board">
            {board.map((id) => (
              <li key={id}>
                <button className="linklike" onClick={() => { setAgentId(id); lookup(id); }}>
                  Agent {id}
                </button>
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="card">
        <h2>How it works</h2>
        <div className="steps">
          {steps.map((s) => (
            <div key={s.n} className="step">
              <span className="num">{s.n}</span>
              <div>
                <strong>{s.t}</strong>
                <p className="muted">{s.d}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="card accent">
        <h2>Why it cannot be farmed</h2>
        <p>
          Every passport is bound to a Self Agent ID human nullifier. The Self
          registry caps how many agents one human can hold and de-duplicates by
          that nullifier, so activity always traces back to a real, unique
          person. This is what makes the Visa qualification trustworthy rather
          than gameable.
        </p>
      </section>

      <section className="card">
        <h2>Architecture</h2>
        <ul className="contracts">
          {contracts.map((c) => (
            <li key={c.address}>
              <div>
                <strong>{c.name}</strong>
                <p className="muted">{c.role}</p>
              </div>
              <a href={scan(c.address)} target="_blank" rel="noreferrer">{short(c.address)}</a>
            </li>
          ))}
        </ul>
      </section>

      <section className="card">
        <h2>For builders</h2>
        <p className="muted">Integrate in a few lines with the published SDK.</p>
        <pre>
{`import { VisaProof } from "visaproof-sdk";

const vp = new VisaProof({ rpcUrl, account, agentId: 9187n });

await vp.registerAgent({ selfAgentId: 140n });
await vp.submitActivity({ txHashes, amounts, tokens: ["cUSD"] });
const { tierName } = await vp.getPassport();
const top = await vp.getLeaderboard({ minTier: "WorkVisa", limit: 10 });`}
        </pre>
      </section>

      <footer>
        VisaProof reads live from Celo mainnet via the visaproof-sdk package.
        Open source, MIT.
      </footer>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="stat">
      <span className="label">{label}</span>
      <span className="value">{value}</span>
    </div>
  );
}
