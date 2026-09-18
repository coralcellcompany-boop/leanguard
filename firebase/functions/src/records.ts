import type { Request } from "express";
import { createHash } from "node:crypto";
import { rows, body, owned, validId, HttpError, hasPro, consent, userTransaction, type Identity } from "./shared/platform.js";
import { localClock } from "./shared/reminders.js";

const consentKinds = ["terms", "privacy", "health_data", "ai_processing", "analytics", "crash_reporting", "notifications"];
export async function consentHandler(req: Request, { uid }: Identity) {
  const input = body(req), row = input.row as Record<string, unknown>;
  if (!row || !validId(row.id) || row.user_id !== uid || !consentKinds.includes(String(row.kind)) || typeof row.granted !== "boolean" || typeof row.policy_version !== "string" || !row.policy_version.length || row.policy_version.length > 40) throw new HttpError(400, "invalid_consent", "Provide a valid consent record.");
  const ref = rows(uid, "consent_records").doc(row.id);
  return userTransaction(uid, async tx => {
    const [existingDoc, stateDoc] = await Promise.all([tx.get(ref), tx.get(rows(uid,"consent_state").doc(String(row.kind)))]);
    const existing = existingDoc.data();
    if (existing) {
      if (existing.kind !== row.kind || existing.granted !== row.granted || existing.policy_version !== row.policy_version) throw new HttpError(409, "immutable_consent", "Consent records cannot be modified. Create a new choice.");
      return existing;
    }
    const timestamp = new Date(Math.max(Date.now(), (stateDoc.data()?.updated_at_ms ?? 0) + 1));
    const result = { ...owned(uid, { kind: row.kind, granted: row.granted, policy_version: row.policy_version }, row.id as string), created_at: timestamp.toISOString() };
    tx.create(ref, result);
    tx.set(rows(uid,"consent_state").doc(String(row.kind)), { granted: row.granted, updated_at_ms: timestamp.getTime(), record_id: row.id });
    return result;
  });
}

function reminderRow(value: unknown, uid: string) {
  if (!value || typeof value !== "object") throw new HttpError(400, "invalid_reminder", "Provide a reminder.");
  const row = value as Record<string, unknown>;
  const time = (x: unknown) => typeof x === "string" && /^([01]\d|2[0-3]):[0-5]\d(?::00)?$/.test(x);
  if (!validId(row.id) || row.user_id !== uid || !["workout", "protein", "walking", "weight", "hydration", "check_in", "weekly"].includes(String(row.kind)) || typeof row.title !== "string" || row.title.length < 1 || row.title.length > 100 || !time(row.time_of_day) || !Array.isArray(row.days_of_week) || !row.days_of_week.length || row.days_of_week.length > 7 || !row.days_of_week.every(n => Number.isInteger(n) && n >= 1 && n <= 7) || typeof row.enabled !== "boolean" || typeof row.smart !== "boolean" || !["local", "push"].includes(String(row.delivery)) || typeof row.time_zone !== "string") throw new HttpError(400, "invalid_reminder", "Check reminder fields and times.");
  if ((row.quiet_start != null || row.quiet_end != null) && (!time(row.quiet_start) || !time(row.quiet_end))) throw new HttpError(400, "invalid_reminder", "Provide both quiet hour times.");
  try { localClock(new Date(), row.time_zone); } catch { throw new HttpError(400, "invalid_time_zone", "Choose a valid time zone."); }
  return owned(uid, { kind: row.kind, title: row.title, time_of_day: row.time_of_day, days_of_week: [...new Set(row.days_of_week)], enabled: row.enabled, smart: row.smart, quiet_start: row.quiet_start ?? null, quiet_end: row.quiet_end ?? null, time_zone: row.time_zone, delivery: row.delivery }, row.id);
}
export async function saveReminderHandler(req: Request, { uid }: Identity) {
  const row = reminderRow(body(req).row, uid), ref = rows(uid, "reminder_preferences").doc(row.id);
  return userTransaction(uid, async tx => {
    const [entitlement, existing, reminders] = await Promise.all([tx.get(rows(uid, "subscription_entitlements").doc("pro")), tx.get(ref), tx.get(rows(uid, "reminder_preferences"))]);
    if (!hasPro(entitlement.data()) && row.enabled) {
      if (row.smart || row.quiet_start != null) throw new HttpError(403, "pro_required", "Smart reminders and quiet hours require Pro.");
      if (reminders.docs.filter(doc => doc.id !== row.id && doc.data().enabled).length >= 3) throw new HttpError(403, "reminder_limit", "Free supports three enabled reminders.");
    }
    // A shared lock document makes concurrent new reminders conflict even when
    // both queries initially see fewer than three records.
    const lock = rows(uid, "server_state").doc("reminders");
    const lockDoc = await tx.get(lock);
    const result = { ...row, created_at: existing.data()?.created_at ?? row.created_at };
    tx.set(lock, { revision: (lockDoc.data()?.revision ?? 0) + 1 }); tx.set(ref, result); return result;
  });
}
export async function deleteReminderHandler(req: Request, { uid }: Identity) {
  const id = body(req).id;
  if (!validId(id)) throw new HttpError(400, "invalid_request", "Provide a reminder ID.");
  await rows(uid, "reminder_preferences").doc(id).delete(); return { deleted: true };
}

export async function healthHandler(req: Request, { uid }: Identity) {
  const input = body(req), date = input.date, steps = input.steps, energy = input.active_energy, source = input.source, weight = input.weight as Record<string, unknown> | undefined;
  const validNumber = (x: unknown, min: number, max: number) => typeof x === "number" && Number.isFinite(x) && x >= min && x <= max;
  const dateMs = typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date) ? Date.parse(`${date}T12:00:00Z`) : NaN;
  if (!Number.isFinite(dateMs) || Math.abs(dateMs - Date.now()) > 8 * 86400000 || dateMs > Date.now() + 86400000 || !["apple_health", "health_connect"].includes(String(source)) || (steps != null && (!validNumber(steps, 0, 200000) || !Number.isInteger(steps))) || (energy != null && !validNumber(energy, 0, 50000))) throw new HttpError(400, "invalid_health_data", "Provide valid recent health readings.");
  if (weight && (!validNumber(weight.kg, 20, 500) || typeof weight.external_id !== "string" || !weight.external_id.length || weight.external_id.length > 256 || typeof weight.recorded_at !== "string" || !Number.isFinite(Date.parse(weight.recorded_at)) || Date.parse(weight.recorded_at) > Date.now() + 86400000 || Date.parse(weight.recorded_at) < Date.now() - 30 * 86400000)) throw new HttpError(400, "invalid_weight", "Provide a valid recent health weight.");
  const dayRef = rows(uid, "daily_activities").doc(String(date)), connectionRef = rows(uid, "health_connections").doc(String(source));
  const weightId = weight ? createHash("sha256").update(`${source}:${weight.external_id}`).digest("hex") : null;
  return userTransaction(uid, async tx => {
    const [entitlement, connection, day, allowed] = await Promise.all([tx.get(rows(uid, "subscription_entitlements").doc("pro")), tx.get(connectionRef), tx.get(dayRef), consent(uid, "health_data", tx)]);
    const weightDoc = weightId ? await tx.get(rows(uid, "weight_entries").doc(weightId)) : null;
    if ((input.background === true || energy != null) && !hasPro(entitlement.data())) throw new HttpError(403, "pro_required", "Background sync and active energy require Pro.");
    if (!allowed || connection.data()?.status !== "connected") throw new HttpError(403, "permission_denied", "Health sharing is not enabled.");
    let activity = day.data() ?? null;
    if (steps != null && (!activity || activity.source !== "manual")) {
      activity = { ...(activity ?? owned(uid, { date, readiness_score: null, energy_level: null }, crypto.randomUUID())), steps, active_energy_kcal: energy ?? activity?.active_energy_kcal ?? 0, source };
      tx.set(dayRef, activity);
    }
    if (weight && weightId && !weightDoc?.exists) tx.create(rows(uid, "weight_entries").doc(weightId), owned(uid, { recorded_at: weight.recorded_at, weight_kg: weight.kg, source, external_id: weight.external_id }, weightId));
    tx.update(connectionRef, { last_synced_at: new Date().toISOString() });
    return { activity, weight_imported: !!weight && !weightDoc?.exists, synced: true };
  });
}
