export type Weight = { weight_kg: number; recorded_at: string };
export type Performance = { exercise_id: string; workout_id: string; recorded_at: string; weight_kg: number; reps: number };
const average = (values: number[]) => values.reduce((a, b) => a + b, 0) / values.length;
const day = 86400000;

/** A review signal, not a clinical assessment. Require repeated observations. */
export function trends(weights: Weight[], sets: Performance[], now = new Date()) {
  const boundary = now.getTime() - 7 * day;
  const start = now.getTime() - 14 * day;
  const byDate = new Map<string, number[]>();
  for (const entry of weights) {
    const when = Date.parse(entry.recorded_at), kg = Number(entry.weight_kg);
    if (!Number.isFinite(when) || !Number.isFinite(kg) || kg <= 0 || when < start || when > now.getTime()) continue;
    const date = new Date(when).toISOString().slice(0, 10);
    byDate.set(date, [...(byDate.get(date) ?? []), kg]);
  }
  const dailyWeights = [...byDate].map(([date, values]) => ({ weight_kg: average(values), recorded_at: `${date}T12:00:00Z` }));
  const recentWeights = dailyWeights.filter((x) => Date.parse(x.recorded_at) >= boundary);
  const priorWeights = dailyWeights.filter((x) => Date.parse(x.recorded_at) < boundary);
  const pace = recentWeights.length >= 2 && priorWeights.length >= 2
    ? (average(priorWeights.map((x) => Number(x.weight_kg))) - average(recentWeights.map((x) => Number(x.weight_kg)))) / average(priorWeights.map((x) => Number(x.weight_kg))) * 100
    : null;
  const scores = new Map<string, { prior: Map<string, number>; recent: Map<string, number> }>();
  for (const set of sets) {
    const when = Date.parse(set.recorded_at);
    if (when < start || when > now.getTime() || set.reps < 1 || set.reps > 12 || set.weight_kg <= 0) continue;
    const value = scores.get(set.exercise_id) ?? { prior: new Map(), recent: new Map() };
    const bucket = when >= boundary ? value.recent : value.prior;
    const score = set.weight_kg * (1 + set.reps / 30);
    bucket.set(set.workout_id, Math.max(score, bucket.get(set.workout_id) ?? 0));
    scores.set(set.exercise_id, value);
  }
  const changes: number[] = [];
  for (const value of scores.values()) {
    if (value.prior.size < 2 || value.recent.size < 2) continue;
    changes.push((average([...value.recent.values()]) / average([...value.prior.values()]) - 1) * 100);
  }
  const strength = changes.length ? average(changes) : null;
  return { weeklyWeightLossPercent: pace, strengthChangePercent: strength, risk: pace !== null && strength !== null && pace > 1 && strength < -5 };
}

export async function hashSnapshot(value: unknown): Promise<string> {
  function canonical(x: unknown): unknown {
    if (Array.isArray(x)) return x.map(canonical);
    if (x && typeof x === "object") return Object.fromEntries(Object.entries(x).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, canonical(v)]));
    return x;
  }
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(canonical(value))));
  return [...new Uint8Array(bytes)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
