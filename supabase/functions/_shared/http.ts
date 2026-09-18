import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export const headers = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "X-Content-Type-Options": "nosniff",
};

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(503, "not_configured", `${name} is not configured`);
  return value;
}

export function admin(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function authenticate(req: Request) {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new HttpError(401, "unauthorized", "Sign in to continue.");
  const token = authorization.slice(7);
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // A server validation call is mandatory; never authorize from getSession or
  // an unverified decoded JWT. All client reads remain scoped through RLS.
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "unauthorized", "Your session expired. Sign in again.");
  return { user: data.user, client, token };
}

export async function body(req: Request, maxBytes = 8192): Promise<Record<string, unknown>> {
  if (!(req.headers.get("Content-Type") ?? "").includes("application/json")) {
    throw new HttpError(415, "invalid_content_type", "Expected JSON.");
  }
  const reader = req.body?.getReader();
  if (!reader) return {};
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > maxBytes) {
      await reader.cancel();
      throw new HttpError(413, "request_too_large", "Request is too large.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes) || "{}");
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw new Error();
    return parsed;
  } catch { throw new HttpError(400, "invalid_json", "Expected a JSON object."); }
}

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers });
}

export function endpoint(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    // Native applications do not need CORS. Web development is opt-in to one
    // exact origin, rather than exposing health data to arbitrary origins.
    const origin = req.headers.get("Origin");
    const allowed = Deno.env.get("ALLOWED_WEB_ORIGIN");
    if (origin && origin !== allowed) return json({ error: "origin_denied" }, 403);
    let response: Response;
    if (req.method === "OPTIONS") response = new Response(null, { status: 204, headers });
    else if (req.method !== "POST") response = json({ error: "method_not_allowed" }, 405);
    else {
      try { response = await handler(req); }
      catch (error) {
        if (error instanceof HttpError) response = json({ error: error.code, message: error.message }, error.status);
        else {
          // No request body, auth headers, database rows, or health data in logs.
          console.error(JSON.stringify({ event: "edge_error", request_id: crypto.randomUUID() }));
          response = json({ error: "unavailable", message: "This service is temporarily unavailable. Please try again." }, 503);
        }
      }
    }
    if (origin && allowed === origin) response.headers.set("Access-Control-Allow-Origin", origin);
    return response;
  };
}

export function must<T>(result: { data: T; error: unknown }): T {
  if (result.error) throw new Error("Database operation failed");
  return result.data;
}

export function uuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export async function secureEqual(value: string, expected: string): Promise<boolean> {
  const digest = async (s: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  const [a, b] = await Promise.all([digest(value), digest(expected)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
