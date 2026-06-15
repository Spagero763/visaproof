"use client";

import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { VisaProof, CELO_MAINNET } from "visaproof-sdk";

const vp = new VisaProof({ rpcUrl: "https://forno.celo.org" });

const contracts = [
  { name: "AgentPassport", address: CELO_MAINNET.passport },
  { name: "AgentActivityOracle", address: CELO_MAINNET.activityOracle },
  { name: "AgentVisaRegistry", address: CELO_MAINNET.visaRegistry },
  { name: "MentoPriceAdapter", address: CELO_MAINNET.priceAdapter },
];

const scan = (addr: string) => `https://celoscan.io/address/${addr}`;

type View = {
  tier: string;
  volume: string;
  txCount: string;
  selfAgentId: string;
  human: boolean;
};

export default function Home() {
  const [agentId, setAgentId] = useState("9187");
  const [data, setData] = useState<View | null>(null);
  const [board, setBoard] = useState<string[]>([]);
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

  async function loadBoard() {
    try {
      const ids = await vp.getLeaderboard({ minTier: "Tourist", limit: 25 });
      setBoard(ids.map((x) => x.toString()));
    } catch {
      setBoard([]);
    }
  }

  useEffect(() => {
    lookup("9187");
    loadBoard();
  }, []);

  return (
    <main>
      <header className="hero">
        <h1>VisaProof</h1>
        <p className="tag">
          On-chain Agent Visa qualification on Celo, gated on a Self Agent ID
          proof of human.
        </p>
        <div className="links">
          <a href="https://github.com/Spagero763/visaproof">GitHub</a>
          <a href="https://www.npmjs.com/package/visaproof-sdk">npm</a>
        </div>
      </header>

      <section className="card">
        <h2>Agent passport</h2>
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
              <span className={data.human ? "badge ok" : "badge bad"}>
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
        <h2>Contracts (Celo mainnet)</h2>
        <ul className="contracts">
          {contracts.map((c) => (
            <li key={c.address}>
              <span>{c.name}</span>
              <a href={scan(c.address)} target="_blank" rel="noreferrer">
                {c.address}
              </a>
            </li>
          ))}
        </ul>
      </section>

      <footer>
        Reads live from Celo mainnet via the visaproof-sdk package.
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
