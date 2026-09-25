import { rows, hasPro, HttpError, nowIso, owned, userTransaction } from "./platform.js";
import type { Kind, CoachReply } from "./coaching.js";

export function periods(now: Date) {
  const monday = new Date(now); monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7);
  return { day: now.toISOString().slice(0, 10), month: now.toISOString().slice(0, 7), week: monday.toISOString().slice(0, 10) };
}
export type Reservation = { status: "cached" | "reserved"; is_pro: boolean; remaining: number; result?: CoachReply; request_id?: string };
/** All reservations for one user conflict on one counter document. The same
 * transaction reads the cache, entitlement and rate windows before spending. */
export async function reserve(uid: string, kind: Kind, key: string, now = new Date()): Promise<Reservation> {
  const time = now.getTime(), p = periods(now);
  const usageRef = rows(uid, "ai_usage").doc("current");
  const cacheRef = rows(uid, "ai_cache").doc(key);
  const requestId = crypto.randomUUID();
  return userTransaction(uid, async (tx) => {
    const [usageDoc, cacheDoc, entitlement] = await Promise.all([tx.get(usageRef), tx.get(cacheRef), tx.get(rows(uid, "subscription_entitlements").doc("pro"))]);
    const pro = hasPro(entitlement.data(), time);
    if (kind === "adaptation" && !pro) throw new HttpError(403, "pro_required", "Plan adaptation is part of LeanGuard Pro.");
    const u = usageDoc.data() ?? {};
    const reservations: Array<{ id: string; at: number; kind: Kind; state: string }> = (u.reservations ?? [])
      .filter((r: { at: number }) => r.at >= time - 32 * 86400000)
      .map((r: { id: string; at: number; kind: Kind; state: string }) => r.state === "reserved" && r.at < time - 60000 ? { ...r, state: "failed" } : r)
      .filter((r: { at: number; state: string }) => r.state !== "failed" || r.at > time - 60000);
    const charged = reservations.filter(r => r.state !== "failed");
    const monthly = charged.filter(r => new Date(r.at).toISOString().startsWith(p.month) && (pro || r.kind === "question")).length;
    const remaining = Math.max(0, (pro ? 100 : 3) - monthly);
    const cache = cacheDoc.data();
    if (cache?.result && cache.expires_ms > time) return { status: "cached", result: cache.result, remaining, is_pro: pro };
    if (cache?.pending_until_ms > time) throw new HttpError(429, "in_progress", "This insight is already being prepared. Try again shortly.");
    if (reservations.filter(r => r.at > time - 60000).length >= 6) throw new HttpError(429, "rate_limited", "Please wait a minute before asking again.");
    const weekly = charged.filter(r => r.kind === "weekly" && periods(new Date(r.at)).week === p.week).length;
    const day = charged.filter(r => r.at > time - 86400000).length;
    if ((pro && (monthly >= 100 || day >= 20)) || (!pro && ((kind === "question" && monthly >= 3) || (kind === "weekly" && weekly >= 1)))) {
      throw new HttpError(429, "quota_exceeded", "Your current coaching allowance is reached. Your existing data remains available.", { remaining });
    }
    reservations.push({ id: requestId, at: time, kind, state: "reserved" });
    tx.set(usageRef, { reservations, updated_at: now.toISOString() });
    tx.set(cacheRef, { pending_until_ms: time + 60000, pending_request_id: requestId }, { merge: true });
    tx.set(rows(uid, "ai_requests").doc(requestId), owned(uid, { kind, cache_key: key, state: "reserved" }, requestId));
    return { status: "reserved", request_id: requestId, is_pro: pro, remaining: (pro || kind === "question") ? Math.max(0, remaining - 1) : remaining };
  });
}
export async function finish(uid: string, reservation: Reservation, cacheKey: string, reply: CoachReply, charged: boolean, kind: Kind): Promise<void> {
  if (!reservation.request_id) return;
  const usageRef = rows(uid, "ai_usage").doc("current"), cacheRef = rows(uid, "ai_cache").doc(cacheKey);
  await userTransaction(uid, async tx => {
    const [usage, cache] = await Promise.all([tx.get(usageRef), tx.get(cacheRef)]);
    const state = charged ? "completed" : "failed";
    const reservations = (usage.data()?.reservations ?? []).map((r: { id: string; state: string }) => r.id === reservation.request_id ? { ...r, state } : r);
    tx.set(usageRef, { reservations, updated_at: nowIso() });
    tx.update(rows(uid, "ai_requests").doc(reservation.request_id!), { state });
    if (cache.data()?.pending_request_id === reservation.request_id) {
      const ttl = charged ? (kind === "weekly" ? 7 * 86400000 : 86400000) : 300000;
      tx.set(cacheRef, owned(uid, { cache_key: cacheKey, result: reply, expires_ms: Date.now() + ttl, expires_at: new Date(Date.now() + ttl).toISOString(), pending_until_ms: 0 }, cacheKey));
    }
  });
}
