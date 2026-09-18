import { admin, endpoint, env, HttpError, json, must, secureEqual } from "../_shared/http.ts";
import { isQuiet, localClock, reminderDue, type Reminder } from "../_shared/reminders.ts";
import { sendPush } from "../_shared/fcm.ts";

Deno.serve(endpoint(async (req) => {
  if (!await secureEqual(req.headers.get("x-cron-secret") ?? "", env("REMINDER_CRON_SECRET"))) throw new HttpError(401, "unauthorized", "Invalid scheduler secret.");
  const db = admin();
  const now = new Date();
  const proByUser = new Map<string, boolean>();
  const consentByUser = new Map<string, boolean>();
  async function pro(userId: string) {
    if (!proByUser.has(userId)) proByUser.set(userId, must(await db.rpc("user_has_pro", { p_user_id: userId })));
    return proByUser.get(userId)!;
  }
  async function consent(userId: string) {
    if (!consentByUser.has(userId)) {
      const row = must(await db.from("consent_records").select("granted").eq("user_id", userId).eq("kind", "notifications").order("created_at", { ascending: false }).limit(1).maybeSingle());
      consentByUser.set(userId, row?.granted === true);
    }
    return consentByUser.get(userId)!;
  }
  let cursor: string | undefined;
  let enqueued = 0;
  while (true) {
    let query = db.from("reminder_preferences").select("*").eq("enabled", true).eq("delivery", "push").order("id").limit(500);
    if (cursor) query = query.gt("id", cursor);
    const reminders = must(await query) as Reminder[];
    for (const reminder of reminders) {
      if (!reminderDue(reminder, now, reminder.smart ? await pro(reminder.user_id) : false) || !await consent(reminder.user_id)) continue;
      const local = localClock(now, reminder.time_zone);
      if (reminder.smart) {
        const [activity, target, goals] = await Promise.all([
          db.from("daily_activities").select("steps").eq("user_id", reminder.user_id).eq("date", local.date).maybeSingle(),
          db.from("daily_targets").select("steps,protein_g").eq("user_id", reminder.user_id).eq("date", local.date).maybeSingle(),
          db.from("goal_profiles").select("step_target,protein_target_g").eq("user_id", reminder.user_id).maybeSingle(),
        ]);
        must(activity); must(target); must(goals);
        if (reminder.kind === "walking" && (activity.data?.steps ?? 0) >= (target.data?.steps ?? goals.data?.step_target ?? 7000)) continue;
        if (reminder.kind === "protein") {
          const meals = must(await db.from("protein_entries").select("protein_g,recorded_at").eq("user_id", reminder.user_id).gte("recorded_at", new Date(now.getTime() - 48 * 3600000).toISOString()).limit(1000)) ?? [];
          const grams = meals.filter((m) => localClock(new Date(m.recorded_at), reminder.time_zone).date === local.date).reduce((sum, m) => sum + Number(m.protein_g), 0);
          if (grams >= (target.data?.protein_g ?? goals.data?.protein_target_g ?? 120)) continue;
        }
        if (reminder.kind === "workout") {
          const workouts = must(await db.from("workouts").select("completed_at").eq("user_id", reminder.user_id).eq("status", "completed").gte("completed_at", new Date(now.getTime() - 48 * 3600000).toISOString()).limit(20)) ?? [];
          if (workouts.some((w) => localClock(new Date(w.completed_at), reminder.time_zone).date === local.date)) continue;
        }
      }
      must(await db.from("notification_deliveries").upsert({ user_id: reminder.user_id, reminder_id: reminder.id, local_date: local.date }, { onConflict: "reminder_id,local_date", ignoreDuplicates: true }));
      enqueued++;
    }
    if (reminders.length < 500) break;
    cursor = reminders.at(-1)!.id;
  }
  const deliveries = must(await db.rpc("claim_notification_deliveries", { p_limit: 50 }));
  let sent = 0;
  for (const delivery of deliveries) {
    try {
      const reminder = must(await db.from("reminder_preferences").select("*").eq("id", delivery.reminder_id).eq("user_id", delivery.user_id).maybeSingle()) as Reminder | null;
      const local = reminder ? localClock(new Date(), reminder.time_zone) : null;
      // Re-check consent, entitlement, latest quiet hours and age at delivery.
      if (!reminder?.enabled || reminder.delivery !== "push" || !await consent(delivery.user_id)
        || (reminder.smart && !await pro(delivery.user_id)) || !local || local.date !== delivery.local_date
        || isQuiet(local.minutes, reminder.quiet_start, reminder.quiet_end) || Date.parse(delivery.created_at) < Date.now() - 30 * 60000) {
        must(await db.from("notification_deliveries").update({ state: "suppressed", leased_until: null }).eq("id", delivery.id));
        continue;
      }
      const tokens = must(await db.from("device_tokens").select("id,token").eq("user_id", delivery.user_id).limit(20)) ?? [];
      let anySent = false;
      for (const device of tokens) {
        const result = await sendPush(device.token, delivery.id);
        if (result === "unregistered") must(await db.from("device_tokens").delete().eq("id", device.id));
        else anySent = true;
      }
      must(await db.from("notification_deliveries").update({ state: anySent ? "sent" : "suppressed", sent_at: anySent ? new Date().toISOString() : null, leased_until: null }).eq("id", delivery.id));
      if (anySent) sent++;
    } catch {
      must(await db.from("notification_deliveries").update({ state: "failed", leased_until: null }).eq("id", delivery.id));
    }
  }
  return json({ enqueued, sent });
}));
