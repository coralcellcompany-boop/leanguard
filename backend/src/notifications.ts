import { getMessaging } from "firebase-admin/messaging";
import { db, rows, consent, isPro, userTransaction } from "./shared/platform.js";
import { localClock, reminderDue, type Reminder } from "./shared/reminders.js";

async function completed(uid: string, reminder: Reminder, date: string): Promise<boolean> {
  if (!reminder.smart) return false;
  const [goals, activities] = await Promise.all([rows(uid, "goal_profiles").doc(uid).get(), rows(uid, "daily_activities").doc(date).get()]);
  const goal = goals.data();
  if (reminder.kind === "walking") return activities.exists && activities.data()!.steps >= (goal?.step_target ?? 7000);
  if (reminder.kind === "workout") {
    const workouts = await rows(uid, "workouts").where("status", "==", "completed").get();
    return workouts.docs.some(doc => doc.data().completed_at && localClock(new Date(doc.data().completed_at), reminder.time_zone).date === date);
  }
  if (reminder.kind === "protein") {
    const start = new Date(Date.now() - 48 * 3600000).toISOString();
    const meals = await rows(uid, "protein_entries").where("recorded_at", ">=", start).get();
    return meals.docs.filter(doc => localClock(new Date(doc.data().recorded_at), reminder.time_zone).date === date).reduce((total, doc) => total + Number(doc.data().protein_g), 0) >= (goal?.protein_target_g ?? 120);
  }
  return false;
}

export async function dispatchReminderRows(now = new Date()): Promise<{ sent: number; suppressed: number }> {
  let cursor, sent = 0, suppressed = 0;
  do {
    let query = db.collectionGroup("reminder_preferences").where("enabled", "==", true).where("delivery", "==", "push").orderBy("__name__").limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      const uid = doc.ref.owner;
      if (!uid || doc.ref.path !== `users/${uid}/reminder_preferences/${doc.id}`) continue;
      const reminder = doc.data() as Reminder;
      if (reminder.user_id !== uid) continue;
      try {
        const pro = await isPro(uid);
        if (!reminderDue(reminder, now, pro) || !await consent(uid, "notifications") || (await db.collection("account_deletions").doc(uid).get()).exists) continue;
        const date = localClock(now, reminder.time_zone).date;
        const deliveryRef = rows(uid, "notification_deliveries").doc(`${doc.id}_${date}`);
        const eligible = await userTransaction(uid, async tx => {
          const previous = (await tx.get(deliveryRef)).data();
          if (previous?.state === "sent" || previous?.state === "suppressed" || previous?.leased_until_ms > Date.now() || previous?.attempts >= 5) return false;
          tx.set(deliveryRef, { id: deliveryRef.id, user_id: uid, reminder_id: doc.id, local_date: date, created_at: previous?.created_at ?? new Date().toISOString(), state: "sending", leased_until_ms: Date.now() + 120000, attempts: (previous?.attempts ?? 0) + 1 });
          return true;
        });
        if (!eligible) continue;
        const fresh = (await doc.ref.get()).data() as Reminder | undefined;
        if (!fresh || !reminderDue(fresh, new Date(), await isPro(uid)) || !await consent(uid, "notifications") || await completed(uid, fresh, date)) {
          await deliveryRef.update({ state: "suppressed" }); suppressed++; continue;
        }
        const tokens = await rows(uid, "device_tokens").limit(500).get();
        if (tokens.empty) { await deliveryRef.update({ state: "failed", leased_until_ms: 0 }); continue; }
        const response = await getMessaging().sendEachForMulticast({
          tokens: tokens.docs.map(doc => doc.data().token),
          notification: { title: "LeanGuard", body: "A reminder for your routine is ready. Open LeanGuard when convenient." },
          data: { route: "/today", delivery_id: deliveryRef.id },
          android: { ttl: 30 * 60000, collapseKey: deliveryRef.id, notification: { channelId: "leanguard_reminders" } },
          apns: { headers: { "apns-collapse-id": deliveryRef.id.slice(0, 64), "apns-expiration": String(Math.floor(Date.now() / 1000) + 1800) }, payload: { aps: { sound: "default" } } },
        });
        for (let i = 0; i < response.responses.length; i++) {
          if (["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(response.responses[i].error?.code ?? "")) await tokens.docs[i].ref.delete();
        }
        await deliveryRef.update({ state: response.successCount > 0 ? "sent" : "failed", leased_until_ms: 0, ...(response.successCount > 0 ? { sent_at: new Date().toISOString() } : {}) });
        sent += response.successCount;
      } catch { console.error(JSON.stringify({ event: "reminder_failure", category: "retryable" })); }
    }
    cursor = page.size === 200 ? page.docs.at(-1) : undefined;
  } while (cursor);
  return { sent, suppressed };
}
