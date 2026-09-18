import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { env, HttpError, must } from "./http.ts";
import { normalizeEntitlement } from "./entitlements.ts";

export async function reconcileEntitlement(db: SupabaseClient, userId: string) {
  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
    headers: { Authorization: `Bearer ${env("REVENUECAT_SECRET_KEY")}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new HttpError(503, "subscription_unavailable", "Subscription verification is temporarily unavailable. Your logged data is still available.");
  const payload = await response.json();
  if (!payload.subscriber || typeof payload.request_date_ms !== "number") throw new Error("Invalid RevenueCat response");
  const entitlement = normalizeEntitlement(payload.subscriber, Date.now(), Deno.env.get("ALLOW_SANDBOX_ENTITLEMENTS") === "true");
  return must(await db.rpc("reconcile_entitlement", {
    p_user_id: userId, p_entitlement: entitlement, p_verified_at: new Date(payload.request_date_ms).toISOString(),
  }));
}
