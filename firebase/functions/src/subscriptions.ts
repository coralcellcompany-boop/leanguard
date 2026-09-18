import type { Request } from "express";
import { auth, db, rows, body, WEBHOOK_SECRET, HttpError, userTransaction, type Identity } from "./shared/platform.js";
import { reconcile, secureEquals } from "./shared/revenuecat.js";

export async function syncHandler(_req: Request, { uid }: Identity) {
  const ref = rows(uid, "server_state").doc("entitlement_sync");
  const cached = await userTransaction(uid, async tx => {
    const [sync, entitlement] = await Promise.all([tx.get(ref), tx.get(rows(uid, "subscription_entitlements").doc("pro"))]);
    if (sync.data()?.next_ms > Date.now()) {
      if (entitlement.exists) return entitlement.data();
      throw new HttpError(429, "rate_limited", "Subscription verification is already running. Try again shortly.");
    }
    tx.set(ref, { next_ms: Date.now() + 15000 }); return null;
  });
  return cached ?? reconcile(uid);
}

export async function webhookHandler(req: Request) {
  const secret = WEBHOOK_SECRET.value();
  if (!secret || secret.length < 24) throw new HttpError(503, "webhook_not_configured", "Webhook authorization is not configured.");
  if (!secureEquals(req.get("Authorization") ?? "", `Bearer ${secret}`)) throw new HttpError(401, "unauthorized", "Invalid webhook authorization.");
  const input = body(req), event = input.event as Record<string, unknown>;
  if (!event || typeof event.id !== "string" || !/^[\w-]{1,200}$/.test(event.id) || typeof event.type !== "string") throw new HttpError(400, "invalid_event", "Invalid RevenueCat webhook event.");
  if (event.type === "TEST") return { received: true, test: true };
  const ref = db.collection("revenuecat_events").doc(event.id);
  if ((await ref.get()).data()?.processed_at) return { received: true, duplicate: true };
  const values = [event.app_user_id, event.original_app_user_id, ...(Array.isArray(event.transferred_from) ? event.transferred_from : []), ...(Array.isArray(event.transferred_to) ? event.transferred_to : [])];
  const ids = [...new Set(values.filter((v): v is string => typeof v === "string" && v.length > 0 && v.length <= 128 && !v.includes("/") && !v.startsWith("$RCAnonymousID:")))].slice(0, 20);
  for (const uid of ids) {
    try { await auth.getUser(uid); } catch (error) {
      if ((error as { code?: string }).code === "auth/user-not-found") continue;
      throw error;
    }
    if ((await db.collection("account_deletions").doc(uid).get()).exists) continue;
    await reconcile(uid); // Fetch current source of truth; event ordering is untrusted.
  }
  await ref.set({ event_type: event.type, processed_at: new Date().toISOString() });
  return { received: true };
}
