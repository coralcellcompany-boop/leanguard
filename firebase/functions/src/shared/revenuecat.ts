import { timingSafeEqual } from "node:crypto";
import { rows, REVENUECAT_KEY, ALLOW_SANDBOX, HttpError, owned, userTransaction } from "./platform.js";
import { normalizeEntitlement } from "./entitlements.js";

export function secureEquals(actual: string, expected: string): boolean {
  const a = Buffer.from(actual), b = Buffer.from(expected);
  return b.length > 0 && a.length === b.length && timingSafeEqual(a, b);
}
export async function reconcile(uid: string) {
  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
    headers: { Authorization: `Bearer ${REVENUECAT_KEY.value()}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new HttpError(503, "subscription_unavailable", "Subscription verification is temporarily unavailable. Your existing data remains available.");
  const payload = await response.json();
  if (!payload.subscriber || typeof payload.request_date_ms !== "number") throw new Error("Invalid subscription response");
  const mirror = normalizeEntitlement(payload.subscriber, Date.now(), ALLOW_SANDBOX.value());
  const accessUntil = mirror.is_active ? Math.max(mirror.expires_at ? Date.parse(mirror.expires_at) : Number.MAX_SAFE_INTEGER, mirror.grace_period_expires_at ? Date.parse(mirror.grace_period_expires_at) : 0) : 0;
  const ref = rows(uid, "subscription_entitlements").doc("pro");
  return userTransaction(uid, async tx => {
    const current = (await tx.get(ref)).data();
    if ((current?.verified_at_ms ?? 0) > payload.request_date_ms) return current;
    const row = { ...owned(uid, mirror, "pro"), created_at: current?.created_at ?? new Date().toISOString(), verified_at: new Date(payload.request_date_ms).toISOString(), verified_at_ms: payload.request_date_ms, access_until_ms: accessUntil };
    tx.set(ref, row);
    return row;
  });
}
