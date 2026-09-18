import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getAppCheck } from "firebase-admin/app-check";
import { getFirestore, type DocumentData, type Transaction } from "firebase-admin/firestore";
import type { Request, Response } from "express";
import { defineSecret, defineString, defineBoolean } from "firebase-functions/params";

if (!getApps().length) initializeApp();
export const db = getFirestore();
export const auth = getAuth();
export const OPENAI_KEY = defineSecret("OPENAI_API_KEY");
export const REVENUECAT_KEY = defineSecret("REVENUECAT_SECRET_KEY");
export const WEBHOOK_SECRET = defineSecret("REVENUECAT_WEBHOOK_SECRET");
export const COACH_MODEL = defineString("OPENAI_COACH_MODEL", { default: "gpt-4.1-mini" });
export const REASONING_MODEL = defineString("OPENAI_REASONING_MODEL", { default: "gpt-4.1" });
export const ALLOW_SANDBOX = defineBoolean("ALLOW_SANDBOX_ENTITLEMENTS", { default: false });
export const region = "europe-west1";
export const nowIso = () => new Date().toISOString();
export const rows = (uid: string, table: string) => db.collection("users").doc(uid).collection(table);
export const owned = <T extends DocumentData>(uid: string, value: T, id: string = crypto.randomUUID()) => ({ ...value, id, user_id: uid, created_at: nowIso() });
export const validId = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string, public extra: Record<string, unknown> = {}) { super(message); }
}
/** Transactions read the deletion marker so an in-flight writer conflicts with
 * account deletion instead of recreating a user's records after cleanup. */
export async function userTransaction<T>(uid: string, operation: (transaction: Transaction) => Promise<T>): Promise<T> {
  return db.runTransaction(async tx => {
    if ((await tx.get(db.collection("account_deletions").doc(uid))).exists) throw new HttpError(409, "account_deleting", "Account deletion is in progress.");
    return operation(tx);
  });
}
export function body(req: Request): Record<string, unknown> {
  if (!req.is("application/json") || !req.body || typeof req.body !== "object" || Array.isArray(req.body) || JSON.stringify(req.body).length > 32000) {
    throw new HttpError(400, "invalid_request", "Send a JSON object smaller than 32 KB.");
  }
  return req.body;
}
export type Identity = { uid: string; authTime: number };
export async function identify(req: Request, allowDeleting = false): Promise<Identity> {
  const token = req.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) throw new HttpError(401, "unauthenticated", "Sign in to continue.");
  if (process.env.FUNCTIONS_EMULATOR !== "true") {
    const check = req.get("X-Firebase-AppCheck");
    try { if (!check) throw new Error(); await getAppCheck().verifyToken(check); }
    catch { throw new HttpError(401, "app_check_required", "App verification failed. Restart the app and try again."); }
  }
  try {
    const decoded = await auth.verifyIdToken(token, true);
    const deleting = await db.collection("account_deletions").doc(decoded.uid).get();
    if (deleting.exists && !allowDeleting) throw new HttpError(409, "account_deleting", "Account deletion is in progress.");
    return { uid: decoded.uid, authTime: decoded.auth_time };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(401, "unauthenticated", "Your session has expired. Sign in again.");
  }
}
export function endpoint(handler: (req: Request, identity: Identity) => Promise<unknown>, options: { authenticated?: boolean; allowDeleting?: boolean } = {}) {
  return async (req: Request, res: Response): Promise<void> => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
    try {
      const identity = options.authenticated === false ? { uid: "", authTime: 0 } : await identify(req, options.allowDeleting);
      res.status(200).json(await handler(req, identity));
    } catch (error) {
      if (error instanceof HttpError) { res.status(error.status).json({ error: error.code, message: error.message, ...error.extra }); return; }
      // Do not log request bodies, user IDs, health records, or provider errors.
      console.error(JSON.stringify({ event: "function_failure", category: "unexpected" }));
      res.status(503).json({ error: "temporarily_unavailable", message: "This service is temporarily unavailable. Your saved data remains available." });
    }
  };
}
export function hasPro(data: DocumentData | undefined, now = Date.now()): boolean {
  return data?.is_active === true && data.entitlement_id === "pro" && Number(data.access_until_ms) > now;
}
export async function isPro(uid: string): Promise<boolean> { return hasPro((await rows(uid, "subscription_entitlements").doc("pro").get()).data()); }
export async function consent(uid: string, kind: string, transaction?: Transaction): Promise<boolean> {
  const ref = rows(uid, "consent_state").doc(kind);
  const result = transaction ? await transaction.get(ref) : await ref.get();
  return result.data()?.granted === true;
}
export async function list(uid: string, table: string, fields: string[], limit = 1000): Promise<DocumentData[]> {
  const snapshot = await rows(uid, table).orderBy("created_at", "desc").limit(limit).select(...fields).get();
  return snapshot.docs.map((doc) => doc.data());
}
