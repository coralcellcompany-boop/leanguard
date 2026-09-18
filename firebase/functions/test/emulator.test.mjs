import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, collection, getDocs } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

process.env.GCLOUD_PROJECT = 'demo-leanguard';
process.env.FUNCTIONS_EMULATOR = 'true';
const { db, rows, consent, identify } = await import('../lib/shared/platform.js');
const { reserve, finish } = await import('../lib/shared/quota.js');
const { approveHandler, coachHandler } = await import('../lib/coach.js');
const { consentHandler, saveReminderHandler, healthHandler } = await import('../lib/records.js');
const { exportHandler } = await import('../lib/privacy.js');
let env;
const iso = '2026-09-18T00:00:00.000Z';
const row = (id, extras = {}, uid = 'alice') => ({ id, user_id: uid, created_at: iso, ...extras });
const req = body => ({ body, is: type => type === 'application/json', get: () => undefined });
const identity = { uid: 'alice', authTime: Date.now() / 1000 };
const path = (table, id, uid = 'alice') => `users/${uid}/${table}/${id}`;
const client = uid => env.authenticatedContext(uid).firestore();
const seed = async (table, id, extra = {}, uid = 'alice') => rows(uid, table).doc(id).set(row(id, extra, uid));
const pro = async (uid = 'alice') => seed('subscription_entitlements', 'pro', { entitlement_id: 'pro', is_active: true, access_until_ms: Date.now() + 86400000 }, uid);
const grant = async (kind, granted = true) => consentHandler(req({ row: row(crypto.randomUUID(), { kind, granted, policy_version: 'test' }) }), identity);
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-leanguard', firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') }, storage: { rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') } });
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env.cleanup(); await db.terminate(); });

test('profile onboarding shape is writable only by its owner; allowlist blocks premium forgery', async () => {
  const data = row('original-uuid', { display_name: 'Alex', units: 'metric', time_zone: 'UTC', onboarding_completed: false });
  await assertSucceeds(setDoc(doc(client('alice'), path('user_profiles','alice')), data));
  await assertFails(getDoc(doc(client('bob'), path('user_profiles','alice'))));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path('user_profiles','alice'))));
  await assertFails(updateDoc(doc(client('alice'), path('user_profiles','alice')), { is_pro: true }));
  await assertFails(updateDoc(doc(client('alice'), path('user_profiles','alice')), { user_id: 'bob' }));
  await assertFails(updateDoc(doc(client('alice'), path('user_profiles','alice')), { id: 'reassigned' }));
});
test('all 20 entity collections isolate owners; server-owned documents cannot be forged', async () => {
  const tables = ['user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','weekly_insights','coach_conversations','coach_messages','reminder_preferences','subscription_entitlements','consent_records'];
  for (const table of tables) {
    await seed(table, 'one');
    await assertSucceeds(getDocs(collection(client('alice'), `users/alice/${table}`)));
    await assertFails(getDocs(collection(client('bob'), `users/alice/${table}`)));
  }
  for (const table of ['subscription_entitlements','weekly_insights','coach_messages','consent_records','plan_proposals','ai_usage','ai_cache','reminder_preferences']) await assertFails(setDoc(doc(client('alice'),path(table,'forged')),row('forged',{is_active:true})));
});
test('workout child rows cannot reference another user parent', async () => {
  await seed('workouts','workout',{},'bob'); await seed('exercises','exercise');
  const data = row('we',{workout_id:'workout',exercise_id:'exercise',position:0,target_sets:3,target_reps:10,target_weight_kg:0,rest_seconds:90,status:'planned'});
  await assertFails(setDoc(doc(client('alice'),path('workout_exercises','we')),data));
  await seed('workouts','workout');
  await assertSucceeds(setDoc(doc(client('alice'),path('workout_exercises','we')),data));
  await assertSucceeds(setDoc(doc(client('alice'),path('workout_sets','we_1')),row('set-uuid',{workout_exercise_id:'we',set_number:1,reps:10,weight_kg:0,completed:true})));
  await assertFails(setDoc(doc(client('alice'),path('workout_sets','duplicate')),row('set-other',{workout_exercise_id:'we',set_number:1,reps:10,weight_kg:0,completed:true})));
});
test('manual logging validates ranges; health rows require server path', async () => {
  const data = row('weight',{recorded_at:iso,weight_kg:80,source:'manual'});
  await assertSucceeds(setDoc(doc(client('alice'),path('weight_entries','weight')),data));
  await assertFails(updateDoc(doc(client('alice'),path('weight_entries','weight')),{weight_kg:-1}));
  await assertFails(updateDoc(doc(client('alice'),path('weight_entries','weight')),{source:'apple_health'}));
  await assertFails(setDoc(doc(client('alice'),path('daily_activities','2026-09-18')),row('day',{date:'2026-09-18',steps:10,source:'apple_health'})));
  await assertSucceeds(setDoc(doc(client('alice'),path('workouts','logged')),row('logged',{name:'Completed session',status:'completed',duration_seconds:600,health_exported_at:iso})));
});
test('Free waist works, advanced measurements require server Pro; expiry keeps data readable', async () => {
  const base = row('measure',{recorded_at:iso,waist_cm:80});
  await assertSucceeds(setDoc(doc(client('alice'),path('body_measurements','measure')),base));
  await assertFails(updateDoc(doc(client('alice'),path('body_measurements','measure')),{chest_cm:95}));
  await pro();
  await assertSucceeds(updateDoc(doc(client('alice'),path('body_measurements','measure')),{chest_cm:95}));
  await rows('alice','subscription_entitlements').doc('pro').update({access_until_ms:Date.now()-1});
  await assertSucceeds(getDoc(doc(client('alice'),path('body_measurements','measure'))));
  await assertSucceeds(updateDoc(doc(client('alice'),path('body_measurements','measure')),{waist_cm:79}));
  await assertFails(updateDoc(doc(client('alice'),path('body_measurements','measure')),{chest_cm:94}));
});
test('GLP-1 mode requires explicit clinician supervision; minimal onboarding rows allowed', async () => {
  const data=row('med',{enabled:true,clinician_supervised:false,appetite_level:'normal'});
  await assertFails(setDoc(doc(client('alice'),path('medication_support_preferences','alice')),data));
  await assertSucceeds(setDoc(doc(client('alice'),path('medication_support_preferences','alice')),{...data,clinician_supervised:true}));
  await assertSucceeds(setDoc(doc(client('alice'),path('goal_profiles','alice')),row('goals',{goal:'lose_weight',goals:['Keep muscle'],protein_target_g:120,step_target:7000,workouts_per_week:3})));
});
test('consent timestamps are trusted and revocation wins; immutable retries do not regrant', async () => {
  const first=await grant('health_data'); assert.equal(await consent('alice','health_data'),true);
  const last=await grant('health_data',false); assert.equal(await consent('alice','health_data'),false);
  assert.ok(last.created_at>first.created_at);
  await consentHandler(req({row:first}),identity); assert.equal(await consent('alice','health_data'),false);
  await assert.rejects(consentHandler(req({row:{...first,granted:false}}),identity),/cannot be modified/);
});
test('parallel Free AI calls reserve exactly three questions; fallback refunds and cache avoids spend', async () => {
  const results=await Promise.allSettled(Array.from({length:5},(_,i)=>reserve('alice','question',`key${i}`)));
  assert.equal(results.filter(x=>x.status==='fulfilled').length,3);
  assert.equal(results.filter(x=>x.status==='rejected'&&x.reason.code==='quota_exceeded').length,2);
  const index=results.findIndex(x=>x.status==='fulfilled'); const reservation=results[index].value;
  const reply={summary:'Fallback',evidence:[],actions:[],safety:'routine',proposal:null,fallback:true};
  await finish('alice',reservation,`key${index}`,reply,false,'question');
  const cached=await reserve('alice','question',`key${index}`); assert.equal(cached.status,'cached'); assert.equal(cached.remaining,1);
  assert.equal((await reserve('alice','question','replacement')).remaining,0);
});
test('same in-flight snapshot is deduplicated, free weekly quota independent, adaptation Pro only', async () => {
  const r=await reserve('alice','weekly','snapshot');
  await assert.rejects(reserve('alice','weekly','snapshot'),e=>e.code==='in_progress');
  await finish('alice',r,'snapshot',{summary:'Week',evidence:[],actions:[],safety:'routine',proposal:null},true,'weekly');
  assert.equal((await reserve('alice','weekly','snapshot')).status,'cached');
  await assert.rejects(reserve('alice','weekly','changed'),e=>e.code==='quota_exceeded');
  assert.equal((await reserve('alice','question','question')).remaining,2);
  await assert.rejects(reserve('alice','adaptation','adapt'),e=>e.code==='pro_required');
});
test('server reminder transaction enforces three Free reminders under concurrency', async () => {
  const make=id=>row(id,{kind:'protein',title:'Protein',time_of_day:'14:00:00',days_of_week:[1,2,3,4,5,6,7],enabled:true,smart:false,quiet_start:null,quiet_end:null,time_zone:'UTC',delivery:'local'});
  const results=await Promise.allSettled(Array.from({length:5},(_,i)=>saveReminderHandler(req({row:make(`reminder${i}`)}),identity)));
  assert.equal(results.filter(x=>x.status==='fulfilled').length,3);
  await pro(); await saveReminderHandler(req({row:{...make('smart'),smart:true,quiet_start:'22:00',quiet_end:'07:00'}}),identity);
});
test('health import preserves manual day, allows Free steps and weight, Pro gates energy/background', async () => {
  await grant('health_data'); await seed('health_connections','apple_health',{provider:'apple_health',status:'connected'});
  const date=new Date().toISOString().slice(0,10), input={date,steps:3000,active_energy:null,source:'apple_health',weight:{kg:80,external_id:'sample',recorded_at:new Date().toISOString()}};
  const first=await healthHandler(req(input),identity); assert.equal(first.weight_imported,true); assert.equal(first.activity.steps,3000);
  assert.equal((await healthHandler(req(input),identity)).weight_imported,false);
  await assert.rejects(healthHandler(req({...input,active_energy:400}),identity),e=>e.code==='pro_required');
  await assert.rejects(healthHandler(req({...input,background:true}),identity),e=>e.code==='pro_required');
  await pro(); await healthHandler(req({...input,active_energy:400,background:true}),identity);
  assert.equal((await healthHandler(req(input),identity)).activity.active_energy_kcal,400);
  await rows('alice','daily_activities').doc(date).update({source:'manual',steps:999});
  assert.equal((await healthHandler(req(input),identity)).activity.steps,999);
  await grant('health_data',false);
  await assert.rejects(healthHandler(req(input),identity),e=>e.code==='permission_denied');
});
test('approved proposals update only owned unstarted workouts and are idempotent', async () => {
  await pro(); await seed('strength_plans','plan',{is_active:true,version:1});
  await seed('workouts','workout',{plan_id:'plan',status:'planned'});
  await seed('workout_exercises','we',{workout_id:'workout',target_weight_kg:50,target_reps:10,target_sets:3});
  await seed('plan_proposals','proposal',{state:'pending',plan_id:'plan',plan_version:1,expires_at:new Date(Date.now()+86400000).toISOString(),changes:[{workout_exercise_id:'we',target_weight_kg:52,target_reps:10,target_sets:3}]});
  const result=await approveHandler(req({proposal_id:'proposal',approved:true}),identity); assert.equal(result.state,'approved');
  assert.equal((await rows('alice','workout_exercises').doc('we').get()).data().target_weight_kg,52);
  assert.equal((await approveHandler(req({proposal_id:'proposal',approved:true}),identity)).state,'approved');
  assert.equal((await rows('alice','strength_plans').doc('plan').get()).data().version,2);
});
test('stale or already-started proposal cannot mutate plan; rejection does not require Pro', async () => {
  await pro(); await seed('strength_plans','plan',{is_active:true,version:1}); await seed('workouts','w',{plan_id:'plan',status:'in_progress'});
  await seed('workout_exercises','we',{workout_id:'w',target_weight_kg:50,target_reps:10,target_sets:3});
  await seed('plan_proposals','p',{state:'pending',plan_id:'plan',plan_version:1,expires_at:new Date(Date.now()+86400000).toISOString(),changes:[{workout_exercise_id:'we',target_weight_kg:52,target_reps:10,target_sets:3}]});
  await assert.rejects(approveHandler(req({proposal_id:'p',approved:true}),identity),e=>e.code==='stale_proposal');
  assert.equal((await approveHandler(req({proposal_id:'p',approved:false}),identity)).state,'rejected');
});
test('warning symptoms bypass provider and quota; routine questions require consent', async () => {
  assert.equal((await coachHandler(req({message:'I fainted',kind:'question'}),identity)).safety,'urgent');
  assert.equal((await rows('alice','ai_requests').get()).size,0);
  await assert.rejects(coachHandler(req({message:'How was my week?',kind:'question'}),identity),e=>e.code==='consent_required');
  await assert.rejects(identify({get:()=>undefined}),e=>e.code==='unauthenticated');
});
test('production app requests require App Check before token verification',async()=>{
  const prior=process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR='false';
  try { await assert.rejects(identify({get:name=>name==='Authorization'?'Bearer invalid-test-token':undefined}),e=>e.code==='app_check_required'); }
  finally { process.env.FUNCTIONS_EMULATOR=prior; }
});
test('Pro monthly and rolling-day limits use authoritative entitlement',async()=>{
  await pro();
  const now=Date.now();
  const withinMonth=new Date(); withinMonth.setUTCDate(1); withinMonth.setUTCHours(1,0,0,0);
  await rows('alice','ai_usage').doc('current').set({reservations:Array.from({length:100},(_,i)=>({id:`used${i}`,at:withinMonth.getTime()+i,kind:'question',state:'completed'}))});
  await assert.rejects(reserve('alice','question','monthly'),e=>e.code==='quota_exceeded');
  await rows('alice','ai_usage').doc('current').set({reservations:Array.from({length:20},(_,i)=>({id:`day${i}`,at:now-120000-i,kind:'question',state:'completed'}))});
  await assert.rejects(reserve('alice','question','daily'),e=>e.code==='quota_exceeded');
});
test('privacy export includes existing records after expiration and never another account', async () => {
  await seed('weight_entries','mine',{weight_kg:80}); await seed('weight_entries','theirs',{weight_kg:90},'bob');
  const data=await exportHandler(req({}),identity); assert.equal(data.tables.weight_entries.length,1); assert.equal(data.tables.weight_entries[0].id,'mine');
});
test('account deletion tombstone denies existing ID token Firestore access',async()=>{
  await seed('weight_entries','mine',{weight_kg:80});
  await db.collection('account_deletions').doc('alice').set({completed_at:new Date().toISOString()});
  await assertFails(getDoc(doc(client('alice'),path('weight_entries','mine'))));
  await assert.rejects(grant('ai_processing'),e=>e.code==='account_deleting');
  await assert.rejects(reserve('alice','question','recreate'),e=>e.code==='account_deleting');
});
test('complete coach fallback persists structured evidence, refunds usage and serves cached retry',async()=>{
  await grant('ai_processing');
  process.env.OPENAI_API_KEY='';
  const result=await coachHandler(req({message:'How do I stay consistent?',kind:'question'}),identity);
  assert.equal(result.fallback,true); assert.equal(result.remaining,3); assert.ok(result.evidence.length>0);
  assert.equal((await rows('alice','coach_messages').get()).size,2);
  const repeated=await coachHandler(req({message:'How do I stay consistent?',kind:'question'}),identity);
  assert.equal(repeated.cached,true); assert.equal(repeated.remaining,3);
});
test('Storage avatars are private and content/size constrained',async()=>{
  const alice=env.authenticatedContext('alice').storage(),bob=env.authenticatedContext('bob').storage();
  const file=ref(alice,'users/alice/avatars/profile.png');
  await assertSucceeds(uploadBytes(file,new Uint8Array([1,2,3]),{contentType:'image/png'}));
  await assertSucceeds(getBytes(file));
  await assertFails(getBytes(ref(bob,'users/alice/avatars/profile.png')));
  await assertFails(uploadBytes(ref(alice,'users/alice/avatars/script.html'),new Uint8Array([1]),{contentType:'text/html'}));
});
