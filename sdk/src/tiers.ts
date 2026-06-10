/** Agent Visa tiers, matching the on-chain `AgentPassport.Tier` enum order. */
export enum Tier {
  Tourist = 0,
  WorkVisa = 1,
  Citizenship = 2,
}

export type TierName = "Tourist" | "WorkVisa" | "Citizenship";

const NAMES: readonly TierName[] = ["Tourist", "WorkVisa", "Citizenship"];

/** Convert an on-chain tier index (0–2) to its name. */
export function tierName(tier: number | bigint): TierName {
  const i = Number(tier);
  const name = NAMES[i];
  if (!name) throw new Error(`Unknown tier index: ${i}`);
  return name;
}

/** Convert a tier name (or numeric tier) to its on-chain index. */
export function tierIndex(tier: TierName | Tier | number): number {
  if (typeof tier === "number") return tier;
  const i = NAMES.indexOf(tier);
  if (i < 0) throw new Error(`Unknown tier name: ${tier}`);
  return i;
}
