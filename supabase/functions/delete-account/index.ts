import { admin, authenticate, body, endpoint, env, HttpError, json, must } from "../_shared/http.ts";

Deno.serve(endpoint(async (req) => {
  const { user } = await authenticate(req);
  const input = await body(req);
  if (input.confirmation !== "DELETE") throw new HttpError(400, "confirmation_required", "Type DELETE to confirm permanent account deletion.");
  const db = admin();
  // Re-authentication must be completed in the client immediately beforehand.
  // last_sign_in_at is supplied by the verified Auth server, not decoded claims.
  if (!user.last_sign_in_at || Date.parse(user.last_sign_in_at) < Date.now() - 10 * 60000) {
    throw new HttpError(401, "reauthentication_required", "Sign in again before permanently deleting your account.");
  }
  // Ask RevenueCat to remove the customer record before deleting Auth. Store
  // subscriptions themselves must be managed with Apple/Google, as explained
  // on the confirmation screen; account deletion cannot cancel store billing.
  if (Deno.env.get("REVENUECAT_SECRET_KEY")) {
    const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(user.id)}`, {
      method: "DELETE", headers: { Authorization: `Bearer ${env("REVENUECAT_SECRET_KEY")}` }, signal: AbortSignal.timeout(10000),
    });
    if (!response.ok && response.status !== 404) throw new HttpError(503, "deletion_retry", "Account deletion could not finish. Please retry.");
  }
  for (const bucket of ["avatars", "exports"]) {
    // This application only creates flat files under a user UUID. Enumerate
    // recursively too so future nested paths cannot leave user files behind.
    const directories = [user.id];
    while (directories.length) {
      const directory = directories.pop()!;
      let offset = 0;
      const paths: string[] = [];
      while (true) {
        const files = must(await db.storage.from(bucket).list(directory, { limit: 100, offset })) ?? [];
        for (const file of files) {
          if (!file.id) directories.push(`${directory}/${file.name}`);
          else paths.push(`${directory}/${file.name}`);
        }
        if (files.length < 100) break;
        offset += 100;
      }
      for (let start = 0; start < paths.length; start += 100) must(await db.storage.from(bucket).remove(paths.slice(start, start + 100)));
    }
  }
  const { error } = await db.auth.admin.deleteUser(user.id);
  if (error) throw new Error("Could not delete auth user");
  // ON DELETE CASCADE removes all owned rows, push tokens, AI data and consent.
  return json({ deleted: true });
}));
