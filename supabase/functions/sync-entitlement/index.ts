import { admin, authenticate, endpoint, json, must } from "../_shared/http.ts";
import { reconcileEntitlement } from "../_shared/revenuecat.ts";

Deno.serve(endpoint(async (req) => {
  const { user } = await authenticate(req);
  const db = admin();
  const recent = must(await db.from("subscription_entitlements").select("*").eq("user_id", user.id).eq("entitlement_id", "pro").maybeSingle());
  // Limit refreshes without trusting any client purchase state. Store webhook
  // reconciliation bypasses this short cooldown.
  if (recent && Date.parse(recent.verified_at) > Date.now() - 15000) return json({ entitlement: recent, cached: true });
  return json({ entitlement: await reconcileEntitlement(db, user.id), cached: false });
}));
