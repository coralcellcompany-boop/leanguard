import type { Request, Response } from "express";
import { pipeline } from "node:stream/promises";
import { auth, db, rows, body, HttpError, REVENUECAT_KEY, userTransaction, type Identity } from "./shared/platform.js";
import { ExportFiles } from "./shared/export-files.js";
import { config } from "./shared/config.js";
import { withOwnerLifecycleLock } from "./database/postgres.js";

export const exportTables = ["user_profiles", "goal_profiles", "health_connections", "medication_support_preferences", "strength_plans", "exercises", "workouts", "workout_exercises", "workout_sets", "daily_targets", "daily_activities", "protein_entries", "weight_entries", "body_measurements", "weekly_insights", "coach_conversations", "coach_messages", "reminder_preferences", "subscription_entitlements", "consent_records", "plan_proposals", "ai_requests", "device_tokens", "notification_deliveries"];
export function exportFiles() {
  return new ExportFiles({ directory: config.exportDirectory, publicBaseUrl: config.publicBaseUrl, signingSecret: config.exportSigningSecret });
}
/** Serialize file creation with deletion across API instances. */
export async function exportHandler(_req: Request, { uid }: Identity) {
  return withOwnerLifecycleLock(uid, signal => exportForOwner(uid, signal));
}
async function exportForOwner(uid: string, signal: AbortSignal) {
  signal.throwIfAborted();
  await userTransaction(uid, async tx => {
    const ref = rows(uid, "server_state").doc("data_export"), last = await tx.get(ref);
    if (last.data()?.next_ms > Date.now()) throw new HttpError(429, "rate_limited", "Please wait a minute before requesting another export.");
    tx.set(ref, { next_ms: Date.now() + 60000 });
  });
  const exportedAt = new Date().toISOString();
  let chunks: string[] = [], bytes = 0, output: Awaited<ReturnType<ExportFiles['create']>> | undefined;
  const write = async (chunk: string) => {
    signal.throwIfAborted();
    bytes += Buffer.byteLength(chunk);
    if (!output && bytes > 20 * 1024 * 1024) {
      output = await exportFiles().create(uid);
      signal.throwIfAborted();
      for (const buffered of chunks) await output.write(buffered);
      chunks = [];
    }
    if (output) await output.write(chunk); else chunks.push(chunk);
  };
  try {
    await write(`{"schema_version":1,"exported_at":${JSON.stringify(exportedAt)},"user_id":${JSON.stringify(uid)},"tables":{`);
    for (let index = 0; index < exportTables.length; index++) {
      const table = exportTables[index]; await write(`${index ? ',' : ''}${JSON.stringify(table)}:[`);
      let cursor, first = true;
      do {
        if ((await db.collection("account_deletions").doc(uid).get()).exists) throw new HttpError(409, 'account_deleting', 'Account deletion is in progress.');
        let query = rows(uid, table).orderBy("__name__").limit(100);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        for (const doc of page.docs) { await write(`${first ? '' : ','}${JSON.stringify(doc.data())}`); first = false; }
        cursor = page.size === 100 ? page.docs.at(-1) : undefined;
      } while (cursor);
      await write(']');
    }
    await write('}}');
    signal.throwIfAborted();
    if (!output) return JSON.parse(chunks.join(''));
    await output.finish();
    signal.throwIfAborted();
    return { schema_version: 1, user_id: uid, download_url: exportFiles().signedUrl(uid, output.name), expires_in_seconds: 600, exported_at: exportedAt };
  } catch (error) {
    await output?.discard().catch(() => undefined);
    throw error;
  }
}

/** The URL itself is a ten-minute bearer capability. Never log its query string. */
export async function downloadHandler(req: Request, res: Response): Promise<void> {
  res.set({ 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
  const uid = String(req.params.uid ?? ''), name = String(req.params.file ?? '');
  try {
    const files = exportFiles();
    if (!files.verify(uid, name, req.query.expires, req.query.signature) || (await db.collection('account_deletions').doc(uid).get()).exists) {
      res.status(404).json({ error: 'export_unavailable', message: 'This export is unavailable or expired. Request a new export.' }); return;
    }
    const file = await files.read(uid, name);
    res.set({ 'Content-Type': 'application/json', 'Content-Length': String(file.bytes), 'Content-Disposition': 'attachment; filename="leanguard-export.json"' });
    await pipeline(file.stream, res);
  } catch {
    if (!res.headersSent) res.status(404).json({ error: 'export_unavailable', message: 'This export is unavailable or expired. Request a new export.' });
    else res.destroy();
  }
}

export async function deleteHandler(req: Request, { uid, authTime }: Identity) {
  if (body(req).confirmation !== "DELETE") throw new HttpError(400, "confirmation_required", "Confirm deletion with DELETE.");
  if (Date.now() / 1000 - authTime > 600) throw new HttpError(401, "recent_login_required", "Sign in again before deleting your account.");
  return withOwnerLifecycleLock(uid, async signal => {
    signal.throwIfAborted();
    const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, { method: "DELETE", headers: { Authorization: `Bearer ${REVENUECAT_KEY.value()}` }, signal: AbortSignal.timeout(10000) });
    if (!response.ok && response.status !== 404) throw new HttpError(503, "deletion_unavailable", "Account deletion could not finish. Please try again shortly.");
    signal.throwIfAborted();
    await db.collection("account_deletions").doc(uid).set({ requested_at: new Date().toISOString() });
    signal.throwIfAborted();
    await exportFiles().removeOwner(uid);
    signal.throwIfAborted();
    await db.recursiveDelete(db.collection("users").doc(uid));
    try { await auth.deleteUser(uid); }
    catch (error) { if ((error as { code?: string }).code !== 'auth/user-not-found') throw error; }
    // Auth ID tokens expire before this tombstone; the worker prunes it after a day.
    await db.collection("account_deletions").doc(uid).set({ completed_at: new Date().toISOString(), expires_at: new Date(Date.now() + 86400000).toISOString() });
    signal.throwIfAborted();
    return { deleted: true, message: "Your LeanGuard account and stored records were deleted. Manage any store subscription separately in Apple or Google subscription settings." };
  });
}
