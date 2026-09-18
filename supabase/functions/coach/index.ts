import { admin, authenticate, body, endpoint, HttpError, json, must, uuid } from "../_shared/http.ts";
import { classifySafety, fallbackReply, PROMPT_VERSION, safetyReply, type CoachReply, type Kind } from "../_shared/coaching.ts";
import { hashSnapshot } from "../_shared/metrics.ts";
import { snapshotFor } from "../_shared/snapshot.ts";
import { generateCoachReply } from "../_shared/openai.ts";

Deno.serve(endpoint(async (req) => {
  const { user, client } = await authenticate(req);
  const input = await body(req);
  const message = typeof input.message === "string" ? input.message.trim() : "";
  const kind = (input.kind ?? "question") as Kind;
  if (!["question", "weekly", "adaptation"].includes(kind) || message.length > 2000 || (kind === "question" && !message)) {
    throw new HttpError(400, "invalid_request", "Provide a question of up to 2,000 characters and a supported request kind.");
  }
  if (input.conversation_id !== undefined && !uuid(input.conversation_id)) throw new HttpError(400, "invalid_conversation", "Invalid conversation.");
  const db = admin();
  let conversationId = input.conversation_id as string | undefined;
  let history: Array<{ role: string; content: string }> = [];
  if (conversationId) {
    const conversation = must(await client.from("coach_conversations").select("id").eq("id", conversationId).maybeSingle());
    if (!conversation) throw new HttpError(404, "conversation_not_found", "Conversation not found.");
    history = (must(await client.from("coach_messages").select("role,content").eq("conversation_id", conversationId).order("created_at", { ascending: false }).limit(8)) ?? []).reverse();
  }
  const classification = classifySafety(message);
  if (classification !== "routine") return json({ ...safetyReply(classification), conversation_id: conversationId ?? null, cached: false });
  const consent = must(await client.from("consent_records").select("granted").eq("kind", "ai_processing").order("created_at", { ascending: false }).limit(1).maybeSingle());
  if (!consent?.granted) throw new HttpError(403, "consent_required", "Allow AI processing in Privacy settings before sharing your recent logs with the coach.");
  const snapshot = await snapshotFor(client, user.id);
  const snapshotHash = await hashSnapshot(snapshot);
  const week = new Date(); week.setUTCDate(week.getUTCDate() - ((week.getUTCDay() + 6) % 7));
  const weekStart = week.toISOString().slice(0, 10);
  const cacheKey = await hashSnapshot({ snapshotHash, kind, message: kind === "weekly" ? "" : message, history: kind === "weekly" ? [] : history, prompt: PROMPT_VERSION, ...(kind === "weekly" ? { week: weekStart } : {}) });
  const reservation = must(await db.rpc("reserve_ai_request", { p_user_id: user.id, p_kind: kind, p_cache_key: cacheKey }));
  if (!["cached", "reserved"].includes(reservation.status)) {
    return json({ error: reservation.status, message: reservation.status === "pro_required" ? "Plan adaptation is part of LeanGuard Pro." : "Your coaching allowance is currently reached. Your existing data remains available.", ...reservation, fallback: fallbackReply(snapshot, kind) }, reservation.status === "pro_required" ? 403 : 429);
  }
  let reply: CoachReply;
  let providerSucceeded = false;
  if (reservation.status === "cached") reply = reservation.result;
  else if (snapshot.risk) reply = fallbackReply(snapshot, kind);
  else {
    const model = kind === "adaptation" && snapshot.exercises.length >= 4
      ? (Deno.env.get("OPENAI_REASONING_MODEL") ?? "gpt-4.1")
      : (Deno.env.get("OPENAI_COACH_MODEL") ?? "gpt-4.1-mini");
    ({ reply, providerSucceeded } = await generateCoachReply({ key: Deno.env.get("OPENAI_API_KEY") ?? "", model, snapshot, kind, message, history, isPro: reservation.is_pro }));
  }
  if (!conversationId) {
    conversationId = crypto.randomUUID();
    must(await db.from("coach_conversations").insert({ id: conversationId, user_id: user.id, title: kind === "weekly" ? "Weekly review" : "Lean Coach" }));
  }
  if (reply.proposal && !reply.proposal.id) {
    const row = must(await db.from("plan_proposals").insert({ user_id: user.id, ...reply.proposal }).select("id").single());
    if (!row) throw new Error("Could not persist proposal");
    reply.proposal.id = row.id;
  }
  if (reply.proposal?.id && reservation.status === "cached") {
    const proposal = must(await client.from("plan_proposals").select("state,expires_at").eq("id", reply.proposal.id).maybeSingle());
    if (!proposal || proposal.state !== "pending" || Date.parse(proposal.expires_at) <= Date.now()) reply = { ...reply, proposal: null };
  }
  must(await db.from("coach_messages").insert([
    { user_id: user.id, conversation_id: conversationId, role: "user", content: message || "Review my week", safety_classification: classification },
    { user_id: user.id, conversation_id: conversationId, role: "assistant", content: reply.summary, structured_content: reply, safety_classification: reply.safety, prompt_version: PROMPT_VERSION },
  ]));
  if (reservation.status === "reserved") {
    // Provider failure does not consume the monthly allowance. A short fallback
    // cache prevents retries from repeatedly calling an unavailable provider.
    const ttl = providerSucceeded || snapshot.risk ? (kind === "weekly" ? 7 * 24 : 24) * 3600000 : 5 * 60000;
    must(await db.from("ai_cache").upsert({ user_id: user.id, cache_key: cacheKey, result: reply, expires_at: new Date(Date.now() + ttl).toISOString() }, { onConflict: "user_id,cache_key" }));
    must(await db.from("ai_requests").update({ state: providerSucceeded || snapshot.risk ? "completed" : "failed" }).eq("id", reservation.request_id).eq("user_id", user.id));
    if (kind === "weekly") {
      must(await db.from("weekly_insights").upsert({ user_id: user.id, week_start: weekStart, snapshot_hash: snapshotHash, prompt_version: PROMPT_VERSION, content: reply }, { onConflict: "user_id,week_start,snapshot_hash,prompt_version" }));
    }
  }
  return json({ ...reply, conversation_id: conversationId, cached: reservation.status === "cached", remaining: reservation.remaining ?? null });
}));
