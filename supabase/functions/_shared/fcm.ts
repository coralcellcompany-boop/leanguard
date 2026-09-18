import { env } from "./http.ts";

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
let cached: { token: string; expires: number; projectId: string } | undefined;

async function credentials() {
  if (cached && cached.expires > Date.now() + 60000) return cached;
  const account = JSON.parse(env("FCM_SERVICE_ACCOUNT_JSON")) as ServiceAccount;
  if (!account.project_id || !account.client_email || !account.private_key) throw new Error("Invalid FCM credentials");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })}`;
  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, "");
  const bytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", bytes, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", signal: AbortSignal.timeout(10000),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${base64url(signature)}` }),
  });
  if (!response.ok) throw new Error("Push authentication failed");
  const data = await response.json();
  if (typeof data.access_token !== "string") throw new Error("Invalid push token");
  cached = { token: data.access_token, expires: Date.now() + Number(data.expires_in ?? 3600) * 1000, projectId: account.project_id };
  return cached;
}

export async function sendPush(token: string, deliveryId: string): Promise<"sent" | "unregistered"> {
  const auth = await credentials();
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(auth.projectId)}/messages:send`, {
    method: "POST", signal: AbortSignal.timeout(10000),
    headers: { Authorization: `Bearer ${auth.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message: {
      token, notification: { title: "LeanGuard", body: "A small step for your day. Open LeanGuard when you are ready." },
      data: { route: "/today", delivery_id: deliveryId },
      android: { priority: "normal", collapse_key: deliveryId, ttl: "1800s" },
      apns: { headers: { "apns-collapse-id": deliveryId, "apns-expiration": String(Math.floor(Date.now() / 1000) + 1800) }, payload: { aps: { sound: "default" } } },
    } }),
  });
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    if (data.error?.details?.some((d: { errorCode?: string }) => d.errorCode === "UNREGISTERED")) return "unregistered";
    throw new Error("Push send failed");
  }
  return "sent";
}
