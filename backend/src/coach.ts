import type { Request } from "express";
import type { DocumentData, DocumentReference } from "./database/postgres.js";
import { body, rows, owned, validId, consent, HttpError, OPENAI_KEY, COACH_MODEL, REASONING_MODEL, userTransaction, type Identity } from "./shared/platform.js";
import { classifySafety, fallbackReply, safetyReply, PROMPT_VERSION, validChange, type Kind, type CoachReply, type Change } from "./shared/coaching.js";
import { hashSnapshot } from "./shared/metrics.js";
import { snapshotFor } from "./shared/snapshot.js";
import { reserve, finish, periods } from "./shared/quota.js";
import { generateCoachReply } from "./shared/openai.js";
import { hasPro, isPro } from "./shared/platform.js";

export async function coachHandler(req: Request, { uid }: Identity) {
  const input = body(req), message = typeof input.message === "string" ? input.message.trim() : "", kind = (input.kind ?? "question") as Kind;
  if (!["question", "weekly", "adaptation"].includes(kind) || message.length > 2000 || (kind === "question" && !message)) throw new HttpError(400, "invalid_request", "Provide a question of up to 2,000 characters and a supported request kind.");
  let conversationId = input.conversation_id as string | undefined;
  let history: Array<{ role: string; content: string }> = [];
  if (conversationId) {
    if (!validId(conversationId) || !(await rows(uid, "coach_conversations").doc(conversationId).get()).exists) throw new HttpError(404, "conversation_not_found", "Conversation not found.");
    const messages = await rows(uid, "coach_messages").where("conversation_id", "==", conversationId).orderBy("created_at", "desc").limit(8).get();
    history = messages.docs.reverse().map(doc => ({ role: doc.data().role, content: doc.data().content }));
  }
  const classification = classifySafety(message);
  if (classification !== "routine") return { ...safetyReply(classification), conversation_id: conversationId ?? null, cached: false };
  if (!await consent(uid, "ai_processing")) throw new HttpError(403, "consent_required", "Allow AI processing in Privacy settings before sharing recent logs with the coach.");
  const snapshot = await snapshotFor(uid), snapshotHash = await hashSnapshot(snapshot), week = periods(new Date()).week;
  const cacheKey = await hashSnapshot({ snapshotHash, kind, tier: await isPro(uid) ? "pro" : "free", message: kind === "weekly" ? "" : message, history: kind === "weekly" ? [] : history, prompt: PROMPT_VERSION, ...(kind === "weekly" ? { week } : {}) });
  let reservation;
  try { reservation = await reserve(uid, kind, cacheKey); }
  catch (error) { if (error instanceof HttpError) error.extra.fallback = fallbackReply(snapshot, kind); throw error; }
  let reply: CoachReply, providerSucceeded = false;
  if (reservation.status === "cached") reply = reservation.result!;
  else if (snapshot.risk) reply = fallbackReply(snapshot, kind);
  else {
    const model = kind === "adaptation" && snapshot.exercises.length >= 4 ? REASONING_MODEL.value() : COACH_MODEL.value();
    ({ reply, providerSucceeded } = await generateCoachReply({ key: OPENAI_KEY.value(), model, kind, message, snapshot, history, isPro: reservation.is_pro }));
  }
  // Consent may have been revoked while the model was running. Do not persist or
  // expose a newly generated result following a revocation.
  if (!await consent(uid, "ai_processing")) {
    if (reservation.status === "reserved") await finish(uid, reservation, cacheKey, fallbackReply(snapshot, kind), false, kind);
    throw new HttpError(403, "consent_required", "AI processing permission was removed.");
  }
  const writes: Array<{ ref: DocumentReference; data: DocumentData; create: boolean }> = [];
  if (!conversationId) {
    conversationId = crypto.randomUUID();
    writes.push({ ref: rows(uid, "coach_conversations").doc(conversationId), data: owned(uid, { title: kind === "weekly" ? "Weekly review" : "Lean Coach" }, conversationId), create: true });
  }
  if (reply.proposal && !reply.proposal.id) {
    const id = crypto.randomUUID(); reply = { ...reply, proposal: { ...reply.proposal, id } };
    writes.push({ ref: rows(uid, "plan_proposals").doc(id), data: owned(uid, { ...reply.proposal, state: "pending", expires_at: new Date(Date.now() + 7 * 86400000).toISOString() }, id), create: true });
  } else if (reply.proposal?.id) {
    const proposal = (await rows(uid, "plan_proposals").doc(reply.proposal.id).get()).data();
    if (!proposal || proposal.state !== "pending" || Date.parse(proposal.expires_at) <= Date.now()) reply = { ...reply, proposal: null };
  }
  for (const entry of [{ role: "user", content: message || "Review my week", safety_classification: classification }, { role: "assistant", content: reply.summary, structured_content: reply, safety_classification: reply.safety, prompt_version: PROMPT_VERSION }]) {
    const id = crypto.randomUUID(); writes.push({ ref: rows(uid, "coach_messages").doc(id), data: owned(uid, { conversation_id: conversationId, ...entry }, id), create: true });
  }
  if (kind === "weekly") {
    const id = await hashSnapshot({ week, snapshotHash, prompt: PROMPT_VERSION });
    writes.push({ ref: rows(uid, "weekly_insights").doc(id), data: owned(uid, { week_start: week, snapshot_hash: snapshotHash, prompt_version: PROMPT_VERSION, content: reply }, id), create: false });
  }
  await userTransaction(uid, async tx => {
    if (!await consent(uid, "ai_processing", tx)) throw new HttpError(403, "consent_required", "AI processing permission was removed.");
    for (const write of writes) { if (write.create) tx.create(write.ref, write.data); else tx.set(write.ref, write.data); }
  });
  if (reservation.status === "reserved") await finish(uid, reservation, cacheKey, reply, providerSucceeded || snapshot.risk, kind);
  return { ...reply, conversation_id: conversationId, cached: reservation.status === "cached", remaining: reservation.remaining + (reservation.status === "reserved" && !providerSucceeded && !snapshot.risk && (reservation.is_pro || kind === "question") ? 1 : 0) };
}

export async function approveHandler(req: Request, { uid }: Identity) {
  const input = body(req);
  if (!validId(input.proposal_id) || typeof input.approved !== "boolean") throw new HttpError(400, "invalid_request", "Provide a proposal and explicit approval choice.");
  const ref = rows(uid, "plan_proposals").doc(input.proposal_id);
  return userTransaction(uid, async tx => {
    const proposal = (await tx.get(ref)).data();
    if (!proposal) throw new HttpError(404, "proposal_not_found", "Proposal not found.");
    if (proposal.state !== "pending") return { state: proposal.state, proposal_id: proposal.id, plan_id: proposal.plan_id };
    if (!input.approved) { tx.update(ref, { state: "rejected" }); return { state: "rejected", proposal_id: proposal.id }; }
    if (Date.parse(proposal.expires_at) <= Date.now()) { tx.update(ref, { state: "expired" }); return { state: "expired", proposal_id: proposal.id }; }
    const planRef = rows(uid, "strength_plans").doc(proposal.plan_id);
    const [entitlement, planDoc] = await Promise.all([tx.get(rows(uid, "subscription_entitlements").doc("pro")), tx.get(planRef)]);
    if (!hasPro(entitlement.data())) throw new HttpError(403, "pro_required", "Plan adaptation requires an active Pro entitlement.");
    const plan = planDoc.data();
    if (!plan || plan.version !== proposal.plan_version || !plan.is_active) throw new HttpError(409, "stale_proposal", "Your plan changed. Request a fresh adjustment.");
    const changes = proposal.changes as Change[];
    const exercises = await Promise.all(changes.map(change => tx.get(rows(uid, "workout_exercises").doc(change.workout_exercise_id))));
    const workoutIds = [...new Set(exercises.map(doc => doc.data()?.workout_id).filter(Boolean))] as string[];
    const workouts = await Promise.all(workoutIds.map(id => tx.get(rows(uid, "workouts").doc(id))));
    for (let i = 0; i < changes.length; i++) {
      const previous = exercises[i].data();
      const workout = workouts.find(doc => doc.id === previous?.workout_id)?.data();
      if (!previous || !workout || workout.status !== "planned" || workout.plan_id !== proposal.plan_id || !validChange(changes[i], previous as Change)) throw new HttpError(409, "stale_proposal", "A workout changed or started. Request a fresh adjustment.");
    }
    changes.forEach((change, i) => tx.update(exercises[i].ref, { target_weight_kg: change.target_weight_kg, target_sets: change.target_sets, target_reps: change.target_reps }));
    tx.update(planRef, { version: plan.version + 1, updated_at: new Date().toISOString() });
    tx.update(ref, { state: "approved", approved_at: new Date().toISOString() });
    return { state: "approved", proposal_id: proposal.id, plan_id: proposal.plan_id, version: plan.version + 1 };
  });
}
