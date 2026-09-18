import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifySafety, fallbackReply, safetyReply, validateReply, validChange } from '../lib/shared/coaching.js';
import { normalizeEntitlement } from '../lib/shared/entitlements.js';
import { trends, hashSnapshot } from '../lib/shared/metrics.js';
import { isQuiet, localClock, reminderDue } from '../lib/shared/reminders.js';
import { generateCoachReply } from '../lib/shared/openai.js';

const previous = { workout_exercise_id: 'exercise1', target_weight_kg: 50, target_reps: 10, target_sets: 3 };
const snapshot = { facts: ['2 workouts completed.'], risk: false, preferences: {}, plan: { id: 'plan1', version: 1 }, exercises: [{ ...previous, name: 'Squat' }] };

test('urgent symptoms bypass AI and escalation never includes a plan', () => {
  for (const message of ['I fainted during a set', 'I have chest pain', 'I have severe weakness', "I can't keep water down", 'I have shortness of breath']) {
    assert.equal(classifySafety(message), 'urgent', message);
    const reply = safetyReply(classifySafety(message));
    assert.match(reply.summary, /urgent medical care/);
    assert.equal(reply.proposal, null);
    assert.deepEqual(reply.actions, []);
  }
});
test('pain and dehydration are referred; medication changes never advised', () => {
  assert.equal(classifySafety('My knee has pain after squats'), 'medical_referral');
  assert.equal(classifySafety('I feel dehydrated'), 'medical_referral');
  for (const question of ['Should I increase my Ozempic?', 'What dose should I use?', 'Can I stop GLP-1 medication?', 'Should I change semaglutide dosage?']) assert.equal(classifySafety(question), 'medication_boundary');
  assert.equal(classifySafety('Suggest a protein snack'), 'routine');
});
test('progression bounds cap load at 5%, volume changes, and combined increases', () => {
  assert.equal(validChange({ ...previous, target_weight_kg: 52.5 }, previous), true);
  assert.equal(validChange({ ...previous, target_weight_kg: 53 }, previous), false);
  assert.equal(validChange({ ...previous, target_weight_kg: 52, target_reps: 11 }, previous), false);
  assert.equal(validChange({ ...previous, target_reps: 12, target_sets: 4 }, previous), false);
  assert.equal(validChange({ ...previous, target_reps: 10.5 }, previous), false);
  assert.equal(validChange({ ...previous, target_weight_kg: 39 }, previous), false);
  assert.equal(validChange({ ...previous, target_weight_kg: 40 }, previous), true);
});
test('AI output must cite actual facts and proposal must use current owned plan', () => {
  const reply = { summary: 'Keep a steady routine.', evidence: snapshot.facts, actions: [], safety: 'routine', proposal: null };
  assert.equal(validateReply(reply, snapshot, 'question').fallback, false);
  assert.throws(() => validateReply({ ...reply, evidence: ['Invented fact'] }, snapshot, 'question'));
  assert.throws(() => validateReply({ ...reply, actions: ['a', 'b', 'c', 'd'] }, snapshot, 'weekly'));
  const proposal = { plan_id: 'other', plan_version: 1, rationale: 'Good progress', changes: [previous] };
  assert.throws(() => validateReply({ ...reply, proposal }, snapshot, 'adaptation'));
  assert.throws(() => validateReply({ ...reply, proposal: { ...proposal, plan_id: 'plan1' } }, snapshot, 'question'));
  assert.equal(validateReply({ ...reply, summary: 'Increase your semaglutide dose' }, snapshot, 'question').safety, 'medication_boundary');
  const increase = { plan_id: 'plan1', plan_version: 1, rationale: 'Repeated completed targets.', changes: [{ ...previous, target_weight_kg: 52 }] };
  assert.throws(() => validateReply({ ...reply, proposal: increase }, snapshot, 'adaptation'), /Insufficient repeated performance/);
  assert.equal(validateReply({ ...reply, proposal: increase }, { ...snapshot, progression_eligible: ['exercise1'] }, 'adaptation').proposal.changes[0].target_weight_kg, 52);
});
test('provider failures return useful deterministic advice with no mutation', () => {
  const reply = fallbackReply(snapshot, 'adaptation');
  assert.equal(reply.fallback, true);
  assert.equal(reply.proposal, null);
  assert.match(reply.summary, /has not changed/);
  assert.equal(fallbackReply({ ...snapshot, risk: true }, 'weekly').safety, 'medical_referral');
});
test('ordinary logged-fact wording stays routine while diagnosis is referred',()=>{
  const reply={summary:'You have completed two workouts.',evidence:snapshot.facts,actions:[],safety:'routine',proposal:null};
  assert.equal(validateReply(reply,snapshot,'weekly').safety,'routine');
  assert.equal(validateReply({...reply,summary:'You have sarcopenia.'},snapshot,'weekly').safety,'medical_referral');
});
test('Responses transport sends strict schema without storage and validates actual output', async () => {
  const request = { key: 'test-only', model: 'test-model', kind: 'question', snapshot, message: 'How was my week?', history: [], isPro: false };
  const result = await generateCoachReply(request, async (url, options) => {
    assert.equal(url, 'https://api.openai.com/v1/responses');
    const payload = JSON.parse(options.body);
    assert.equal(payload.store, false);
    assert.equal(payload.text.format.strict, true);
    assert.equal(payload.text.format.type, 'json_schema');
    assert.ok(options.signal instanceof AbortSignal);
    return Response.json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ summary: 'Keep your routine steady.', evidence: snapshot.facts, actions: [], safety: 'routine', proposal: null }) }] }] });
  });
  assert.equal(result.providerSucceeded, true);
  assert.equal(result.reply.summary, 'Keep your routine steady.');
});
test('HTTP failure, timeout, invalid JSON, incomplete and refusal all fail safely without consuming provider success', async () => {
  const request = { key: 'test-only', model: 'test-model', kind: 'adaptation', snapshot, message: 'Adjust my plan', history: [], isPro: true };
  const transports = [
    async () => new Response('rate limited', { status: 429 }),
    async () => { throw new DOMException('Timed out', 'TimeoutError'); },
    async () => Response.json({ status: 'incomplete', output: [] }),
    async () => Response.json({ status: 'completed', output: [{ content: [{ type: 'refusal', refusal: 'No' }] }] }),
    async () => Response.json({ status: 'completed', output: [{ content: [{ type: 'output_text', text: 'not json' }] }] }),
  ];
  for (const transport of transports) {
    const result = await generateCoachReply(request, transport);
    assert.equal(result.providerSucceeded, false);
    assert.equal(result.reply.fallback, true);
    assert.equal(result.reply.proposal, null);
  }
});
test('RevenueCat cancellation retains access until expiry, restoration reactivates', () => {
  const now = Date.parse('2026-09-18T00:00:00Z');
  const subscriber = { entitlements: { pro: { expires_date: '2026-10-01T00:00:00Z', product_identifier: 'annual' } }, subscriptions: { annual: { unsubscribe_detected_at: '2026-09-17T00:00:00Z' } } };
  assert.equal(normalizeEntitlement(subscriber, now).is_active, true);
  assert.equal(normalizeEntitlement(subscriber, now).status, 'cancelled');
  assert.equal(normalizeEntitlement(subscriber, Date.parse('2026-10-02')).is_active, false);
  delete subscriber.subscriptions.annual.unsubscribe_detected_at;
  assert.equal(normalizeEntitlement(subscriber, now).status, 'active');
});
test('RevenueCat grace, billing issue, trial, refunds, sandbox and expiry are distinct', () => {
  const now = Date.parse('2026-09-18');
  const subscriber = { entitlements: { pro: { expires_date: '2026-09-17', product_identifier: 'annual' } }, subscriptions: { annual: { grace_period_expires_date: '2026-09-20', billing_issues_detected_at: '2026-09-17' } } };
  assert.equal(normalizeEntitlement(subscriber, now).status, 'grace_period');
  assert.equal(normalizeEntitlement(subscriber, now).is_active, true);
  assert.equal(normalizeEntitlement(subscriber, Date.parse('2026-09-21')).is_active, false);
  subscriber.subscriptions.annual.refunded_at = '2026-09-18';
  assert.equal(normalizeEntitlement(subscriber, now).is_active, false);
  delete subscriber.subscriptions.annual.refunded_at;
  subscriber.subscriptions.annual.is_sandbox = true;
  assert.equal(normalizeEntitlement(subscriber, now).is_active, false);
  assert.equal(normalizeEntitlement(subscriber, now, true).is_active, true);
  assert.equal(normalizeEntitlement({}, now).is_active, false);
});
test('weight plus comparable declining strength raises a conservative review signal', () => {
  const now = new Date('2026-09-18T00:00:00Z');
  const weights = [{ weight_kg: 100, recorded_at: '2026-09-06' }, { weight_kg: 100, recorded_at: '2026-09-08' }, { weight_kg: 98, recorded_at: '2026-09-14' }, { weight_kg: 98, recorded_at: '2026-09-16' }];
  const sets = ['2026-09-06', '2026-09-08', '2026-09-14', '2026-09-16'].map((date, i) => ({ exercise_id: 'squat', workout_id: `session${i}`, recorded_at: date, reps: 8, weight_kg: i < 2 ? 100 : 90 }));
  const result = trends(weights, sets, now);
  assert.equal(result.risk, true);
  assert.equal(result.weeklyWeightLossPercent, 2);
  assert.equal(Math.round(result.strengthChangePercent), -10);
  assert.equal(trends(weights, sets.slice(0, 3), now).risk, false);
  assert.equal(trends([], [], now).weeklyWeightLossPercent, null);
  assert.equal(trends(weights, sets.map((s, i) => ({ ...s, exercise_id: i < 2 ? 'squat' : 'press' })), now).strengthChangePercent, null);
});
test('snapshot cache key is stable across key ordering but changes with data', async () => {
  assert.equal(await hashSnapshot({ b: 2, a: 1 }), await hashSnapshot({ a: 1, b: 2 }));
  assert.notEqual(await hashSnapshot({ a: 1 }), await hashSnapshot({ a: 2 }));
});
test('multiple weigh-ins on one date do not manufacture repeated trend observations',()=>{
  const now=new Date('2026-09-18T00:00:00Z');
  const weights=[{weight_kg:100,recorded_at:'2026-09-07T08:00:00Z'},{weight_kg:100,recorded_at:'2026-09-07T09:00:00Z'},{weight_kg:98,recorded_at:'2026-09-16T08:00:00Z'},{weight_kg:98,recorded_at:'2026-09-16T09:00:00Z'}];
  assert.equal(trends(weights,[],now).weeklyWeightLossPercent,null);
});
test('quiet hours cross midnight and scheduler respects timezone, channel and tier', () => {
  assert.equal(isQuiet(23 * 60, '22:00', '07:00'), true);
  assert.equal(isQuiet(6 * 60, '22:00', '07:00'), true);
  assert.equal(isQuiet(7 * 60, '22:00', '07:00'), false);
  assert.equal(isQuiet(12 * 60, '12:00', '12:00'), true);
  const reminder = { id: '1', user_id: 'a', kind: 'walking', enabled: true, smart: false, time_of_day: '09:00', days_of_week: [5], time_zone: 'Africa/Cairo', quiet_start: null, quiet_end: null, delivery: 'push' };
  const now = new Date('2026-09-18T06:03:00Z');
  assert.equal(localClock(now, reminder.time_zone).minutes, 543);
  assert.equal(reminderDue(reminder, now), true);
  assert.equal(reminderDue({ ...reminder, delivery: 'local' }, now), false);
  assert.equal(reminderDue({ ...reminder, smart: true }, now), false);
  assert.equal(reminderDue({ ...reminder, smart: true }, now, true), true);
});
