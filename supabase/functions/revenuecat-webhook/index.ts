import { admin, body, endpoint, env, HttpError, json, must, secureEqual, uuid } from "../_shared/http.ts";
import { reconcileEntitlement } from "../_shared/revenuecat.ts";

Deno.serve(endpoint(async (req) => {
  // Configure RevenueCat's Authorization header to this exact high-entropy value.
  if (!await secureEqual(req.headers.get("Authorization") ?? "", `Bearer ${env("REVENUECAT_WEBHOOK_SECRET")}`)) throw new HttpError(401, "unauthorized", "Invalid webhook authorization.");
  const payload = await body(req, 65536);
  const event = payload.event as Record<string, unknown> | undefined;
  if (!event || typeof event.id !== "string" || event.id.length > 200 || typeof event.type !== "string") throw new HttpError(400, "invalid_event", "Invalid webhook event.");
  const db = admin();
  const existing = must(await db.from("revenuecat_events").select("processed_at").eq("id", event.id).maybeSingle());
  if (existing?.processed_at) return json({ received: true, duplicate: true });
  const values = [event.app_user_id, event.original_app_user_id,
    ...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
    ...(Array.isArray(event.transferred_to) ? event.transferred_to : [])];
  const users = [...new Set(values.filter(uuid))];
  for (const userId of users) {
    const { data, error } = await db.auth.admin.getUserById(userId);
    if (error?.status === 404 || !data.user) continue;
    if (error) throw new Error("Could not verify webhook user");
    // Re-fetch authoritative state instead of trusting order or partial event
    // payloads. Transfer events reconcile both former and current owners.
    await reconcileEntitlement(db, userId);
  }
  must(await db.from("revenuecat_events").upsert({ id: event.id, event_type: event.type, processed_at: new Date().toISOString() }));
  return json({ received: true });
}));
