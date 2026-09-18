import type { Request } from "express";
import type { Writable } from "node:stream";
import { getStorage } from "firebase-admin/storage";
import { auth, db, rows, body, HttpError, REVENUECAT_KEY, userTransaction, type Identity } from "./shared/platform.js";

export const exportTables = ["user_profiles", "goal_profiles", "health_connections", "medication_support_preferences", "strength_plans", "exercises", "workouts", "workout_exercises", "workout_sets", "daily_targets", "daily_activities", "protein_entries", "weight_entries", "body_measurements", "weekly_insights", "coach_conversations", "coach_messages", "reminder_preferences", "subscription_entitlements", "consent_records", "plan_proposals", "ai_requests", "device_tokens", "notification_deliveries"];
export async function exportHandler(_req: Request, { uid }: Identity) {
  await userTransaction(uid, async tx => {
    const ref = rows(uid,"server_state").doc("data_export"), last = await tx.get(ref);
    if (last.data()?.next_ms > Date.now()) throw new HttpError(429,"rate_limited","Please wait a minute before requesting another export.");
    tx.set(ref,{next_ms:Date.now()+60000});
  });
  const exportedAt = new Date().toISOString(), name = `exports/${uid}/${crypto.randomUUID()}.json`;
  let chunks: string[] = [], bytes = 0, stream: Writable | null = null;
  const write = async (chunk: string) => {
    bytes += Buffer.byteLength(chunk);
    if (!stream && bytes > 20 * 1024 * 1024) {
      stream = getStorage().bucket().file(name).createWriteStream({ resumable:false, metadata:{contentType:"application/json",cacheControl:"private, no-store"} });
      // write/end callbacks below propagate failures; keep the EventEmitter's
      // parallel error notification from becoming an unhandled process error.
      stream.on("error",()=>undefined);
      const buffered = chunks.join(""); chunks=[];
      await new Promise<void>((resolve,reject) => stream!.write(buffered,error=>error?reject(error):resolve()));
    }
    if (stream) await new Promise<void>((resolve,reject) => stream!.write(chunk,error=>error?reject(error):resolve()));
    else chunks.push(chunk);
  };
  try {
    await write(`{"schema_version":1,"exported_at":${JSON.stringify(exportedAt)},"user_id":${JSON.stringify(uid)},"tables":{`);
    for (let index=0; index<exportTables.length; index++) {
      const table=exportTables[index]; await write(`${index ? "," : ""}${JSON.stringify(table)}:[`);
      let cursor, first=true;
      do {
        let query = rows(uid, table).orderBy("__name__").limit(100);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        for (const doc of page.docs) { await write(`${first?"":","}${JSON.stringify(doc.data())}`); first=false; }
        cursor = page.size === 100 ? page.docs.at(-1) : undefined;
      } while (cursor);
      await write("]");
    }
    await write("}}");
    if (!stream) return JSON.parse(chunks.join(""));
    const output: Writable = stream;
    await new Promise<void>((resolve,reject)=>{output.once("error",reject);output.end(resolve);});
    const [url] = await getStorage().bucket().file(name).getSignedUrl({ action: "read", expires: Date.now() + 10 * 60000 });
    return { schema_version: 1, download_url: url, expires_in_seconds: 600, exported_at: exportedAt };
  } catch (error) {
    if (stream) { (stream as Writable).destroy(); await getStorage().bucket().file(name).delete({ignoreNotFound:true}).catch(()=>undefined); }
    throw error;
  }
}
export async function deleteHandler(req: Request, { uid, authTime }: Identity) {
  if (body(req).confirmation !== "DELETE") throw new HttpError(400, "confirmation_required", "Confirm deletion with DELETE.");
  if (Date.now() / 1000 - authTime > 600) throw new HttpError(401, "recent_login_required", "Sign in again before deleting your account.");
  // Delete the third-party account first. A provider outage must not strand the
  // user without a session able to retry the deletion request.
  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, { method: "DELETE", headers: { Authorization: `Bearer ${REVENUECAT_KEY.value()}` }, signal: AbortSignal.timeout(10000) });
  if (!response.ok && response.status !== 404) throw new HttpError(503, "deletion_unavailable", "Account deletion could not finish. Please try again shortly.");
  await db.collection("account_deletions").doc(uid).set({ requested_at: new Date().toISOString() });
  await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
  await getStorage().bucket().deleteFiles({ prefix: `exports/${uid}/` });
  await db.recursiveDelete(db.collection("users").doc(uid));
  await auth.deleteUser(uid);
  // Keep a minimal tombstone until all already-issued ID tokens have expired.
  // Configure Firestore TTL on expires_at to remove it after one day.
  await db.collection("account_deletions").doc(uid).set({ completed_at: new Date().toISOString(), expires_at: new Date(Date.now() + 86400000) });
  return { deleted: true, message: "Your LeanGuard account and stored records were deleted. Manage any store subscription separately in Apple or Google subscription settings." };
}
