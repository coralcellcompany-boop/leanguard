import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';
if (!process.env.TEST_DATABASE_URL || !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')) throw new Error('TEST_DATABASE_URL must point to an isolated *_test database.');
if (!process.env.TEST_ADMIN_DATABASE_URL || !new URL(process.env.TEST_ADMIN_DATABASE_URL).pathname.endsWith('_test')) throw new Error('TEST_ADMIN_DATABASE_URL must point to the same isolated test database.');
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
process.env.EXPORT_SIGNING_SECRET = 'test-export-secret-at-least-thirty-two-characters';
process.env.PUSH_NOTIFICATIONS_ENABLED = 'false';
process.env.FIREBASE_PROJECT_ID = 'demo-leanguard';
const { db, rows, consent, identify, auth, withUserDb, withUserSql } = await import('../lib/shared/platform.js');
const {pool}=await import('../lib/database/postgres.js');
const { reserve, finish } = await import('../lib/shared/quota.js');
const { approveHandler, coachHandler } = await import('../lib/coach.js');
const { consentHandler, saveReminderHandler, healthHandler } = await import('../lib/records.js');
const { exportHandler } = await import('../lib/privacy.js');
const {runJobs}=await import('../lib/jobs.js');
const admin=new pg.Client({connectionString:process.env.TEST_ADMIN_DATABASE_URL});
const iso='2026-09-18T00:00:00.000Z';
const row=(id,extras={},uid='alice')=>({id,user_id:uid,created_at:iso,...extras});
const req=body=>({body,is:type=>type==='application/json',get:()=>undefined});
const identity={uid:'alice',authTime:Date.now()/1000};
const seed=async(table,id,extra={},uid='alice')=>rows(uid,table).doc(id).set(row(id,extra,uid));
const pro=async(uid='alice')=>seed('subscription_entitlements','pro',{entitlement_id:'pro',is_active:true,access_until_ms:Date.now()+86400000},uid);
const grant=async(kind,granted=true)=>consentHandler(req({row:row(crypto.randomUUID(),{kind,granted,policy_version:'test'})}),identity);
const own=(uid,fn)=>withUserDb(uid,sql=>fn(sql.collection('users').doc(uid)));
let exportDirectory;
before(async()=>{await admin.connect();exportDirectory=await mkdtemp(path.join(os.tmpdir(),'leanguard-pg-export-'));process.env.EXPORT_DIRECTORY=exportDirectory;});
beforeEach(async()=>{await admin.query('TRUNCATE app_records CASCADE');});
after(async()=>{await admin.end();await db.terminate();await rm(exportDirectory,{recursive:true,force:true});});
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
test('account deletion tombstone denies tenant reads and further server writes',async()=>{
  await seed('weight_entries','mine',{weight_kg:80});
  await db.collection('account_deletions').doc('alice').set({completed_at:new Date().toISOString()});
  assert.equal((await withUserDb('alice',sql=>sql.collection('users').doc('alice').collection('weight_entries').get())).size,0);
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

test('database RLS scopes all 20 entities and prevents private record reads and premium forgery',async()=>{
  const tables=['user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','weekly_insights','coach_conversations','coach_messages','reminder_preferences','subscription_entitlements','consent_records'];
  for(const table of tables){await seed(table,'one');await seed(table,'other',{},'bob');}
  const mine=await withUserSql('alice',c=>c.query('SELECT DISTINCT owner FROM app_records'));
  assert.deepEqual(mine.rows,[{owner:'alice'}]);
  for(const table of tables)assert.equal((await own('alice',u=>u.collection(table).get())).size,1);
  for(const table of ['subscription_entitlements','weekly_insights','coach_messages','consent_records','plan_proposals','ai_usage','ai_cache','reminder_preferences','device_tokens']){
    await assert.rejects(own('alice',u=>u.collection(table).doc('forged').set(row('forged',{is_active:true}))));
  }
  await rows('alice','ai_cache').doc('cache').set({result:{secret:true}});
  assert.equal((await own('alice',u=>u.collection('ai_cache').get())).size,0);
  await assert.rejects(withUserSql('alice',c=>c.query('INSERT INTO app_records(collection,owner,id,data) VALUES($1,$2,$3,$4)', ['coach_conversations','bob','forged',JSON.stringify(row('forged',{title:'Bad'},'bob'))])));
});
test('client field allowlists, immutable identity and canonical IDs enforced by SQL',async()=>{
  const profile=row('original',{display_name:'Alex',units:'metric',time_zone:'UTC',onboarding_completed:false});
  await own('alice',u=>u.collection('user_profiles').doc('alice').set(profile));
  for(const change of [{is_pro:true},{user_id:'bob'},{id:'different'},{created_at:'2030-01-01T00:00:00Z'}])await assert.rejects(own('alice',u=>u.collection('user_profiles').doc('alice').set({...profile,...change})));
  await assert.rejects(own('alice',u=>u.collection('user_profiles').doc('another').set(profile)));
  await assert.rejects(own('alice',u=>u.collection('weight_entries').doc('w').set(row('w',{weight_kg:-1,source:'manual',recorded_at:iso}))));
  await assert.rejects(own('alice',u=>u.collection('weight_entries').doc('w').set(row('w',{weight_kg:80,source:'apple_health',recorded_at:iso}))));
});
test('composite foreign keys prevent cross-owner parents and cascade workout children',async()=>{
  await seed('workouts','w',{name:'Session'},'bob');await seed('exercises','e');
  const data=row('we',{workout_id:'w',exercise_id:'e',position:0,target_sets:3,target_reps:10,target_weight_kg:0,rest_seconds:90,status:'planned'});
  await assert.rejects(own('alice',u=>u.collection('workout_exercises').doc('we').set(data)),e=>e.code==='23503');
  await seed('workouts','w');await own('alice',u=>u.collection('workout_exercises').doc('we').set(data));
  await own('alice',u=>u.collection('workout_sets').doc('we_1').set(row('set-uuid',{workout_exercise_id:'we',set_number:1,reps:10,weight_kg:0,completed:true})));
  await assert.rejects(own('alice',u=>u.collection('workout_sets').doc('duplicate').set(row('dup',{workout_exercise_id:'we',set_number:1,reps:10,weight_kg:0,completed:true}))));
  await rows('alice','workouts').doc('w').delete();
  assert.equal((await rows('alice','workout_exercises').get()).size,0);assert.equal((await rows('alice','workout_sets').get()).size,0);
  assert.equal((await rows('bob','workouts').get()).size,1);
});
test('advanced measurement creation uses entitlement; expired users retain reads and waist edits',async()=>{
  const base=row('m',{recorded_at:iso,waist_cm:80});
  await own('alice',u=>u.collection('body_measurements').doc('m').set(base));
  await assert.rejects(own('alice',u=>u.collection('body_measurements').doc('m').set({...base,chest_cm:95})));
  await pro();await own('alice',u=>u.collection('body_measurements').doc('m').set({...base,chest_cm:95}));
  await rows('alice','subscription_entitlements').doc('pro').update({access_until_ms:Date.now()-1});
  assert.equal((await own('alice',u=>u.collection('body_measurements').doc('m').get())).data().chest_cm,95);
  await own('alice',u=>u.collection('body_measurements').doc('m').set({...base,waist_cm:79,chest_cm:95}));
  await assert.rejects(own('alice',u=>u.collection('body_measurements').doc('m').set({...base,chest_cm:96})));
});
test('query pagination, collection groups, filtering, projection and merge preserve values',async()=>{
  for(let i=0;i<6;i++)await seed('protein_entries',`p${i}`,{protein_g:i+1,recorded_at:`2026-09-${20+i}`,meal_type:i%2?'lunch':'dinner'});
  const first=await rows('alice','protein_entries').where('protein_g','>=',2).orderBy('protein_g','desc').limit(2).get();
  assert.deepEqual(first.docs.map(d=>d.data().protein_g),[6,5]);
  const next=await rows('alice','protein_entries').where('protein_g','>=',2).orderBy('protein_g','desc').startAfter(first.docs.at(-1)).limit(2).get();
  assert.deepEqual(next.docs.map(d=>d.data().protein_g),[4,3]);
  assert.deepEqual((await rows('alice','protein_entries').orderBy('__name__').offset(2).limit(1).select('id').get()).docs[0].data(),{id:'p2'});
  await rows('alice','protein_entries').doc('p2').set({protein_g:20},{merge:true});assert.equal((await rows('alice','protein_entries').doc('p2').get()).data().recorded_at,'2026-09-22');
  await seed('protein_entries','p0',{protein_g:99},'bob');
  const group=await db.collectionGroup('protein_entries').orderBy('__name__').limit(6).get();
  const last=await db.collectionGroup('protein_entries').orderBy('__name__').startAfter(group.docs.at(-1)).get();
  assert.equal(last.docs[0].ref.owner,'bob');
});
test('auth enforces revoked token verification and verified email without App Check dependency',async()=>{
  const previous=auth.verifyIdToken;let checked=false;
  try{
    auth.verifyIdToken=async(_token,checkRevoked)=>{checked=checkRevoked;return {uid:'alice',auth_time:123,email_verified:true};};
    assert.deepEqual(await identify({get:name=>name==='Authorization'?'Bearer valid-test-token':undefined}),{uid:'alice',authTime:123});assert.equal(checked,true);
    auth.verifyIdToken=async()=>({uid:'alice',auth_time:123,email_verified:false});
    await assert.rejects(identify({get:()=> 'Bearer valid-test-token'}),e=>e.code==='email_verification_required');
    auth.verifyIdToken=async()=>{throw new Error('revoked');};
    await assert.rejects(identify({get:()=> 'Bearer valid-test-token'}),e=>e.code==='unauthenticated');
  }finally{auth.verifyIdToken=previous;}
});
test('worker advisory lock skips a concurrent scheduler and releases for next execution',async()=>{
  const client=await pool.connect();
  try{await client.query('SELECT pg_advisory_lock($1,$2)',[190917,1]);assert.deepEqual(await runJobs(),{skipped:true});}
  finally{await client.query('SELECT pg_advisory_unlock($1,$2)',[190917,1]);client.release();}
  assert.deepEqual(await runJobs(),{skipped:false});
});


test('operator import validates without writes, commits atomically and permits identical retries',async()=>{
  const filename=path.join(exportDirectory,'import.ndjson');
  const fixture=[{collection:'workout_exercises',owner:'alice',id:'we',data:row('we',{workout_id:'w',exercise_id:'e'})},{collection:'exercises',owner:'alice',id:'e',data:row('e')},{collection:'workouts',owner:'alice',id:'w',data:row('w')}];
  await writeFile(filename,fixture.map(x=>JSON.stringify(x)).join('\n'));
  const execute=promisify(execFile),script=fileURLToPath(new URL('../scripts/import-records.mjs',import.meta.url));
  const options={env:{PATH:process.env.PATH,MIGRATION_DATABASE_URL:process.env.TEST_ADMIN_DATABASE_URL}};
  const dry=await execute(process.execPath,[script,filename],options);assert.equal(JSON.parse(dry.stdout).mode,'validated_rolled_back');assert.equal((await rows('alice','workouts').get()).size,0);
  const applied=await execute(process.execPath,[script,filename,'--apply'],options);assert.equal(JSON.parse(applied.stdout).new_records,3);assert.equal((await rows('alice','workout_exercises').get()).size,1);
  const again=await execute(process.execPath,[script,filename,'--apply'],options);assert.equal(JSON.parse(again.stdout).identical_records,3);
  fixture[1].data.name='conflicting-name';await writeFile(filename,fixture.map(x=>JSON.stringify(x)).join('\n'));
  await assert.rejects(execute(process.execPath,[script,filename,'--apply'],options));assert.equal((await rows('alice','exercises').doc('e').get()).data().name,undefined);
});
test('operator import rolls back cross-owner foreign references without exposing private rows',async()=>{
  const filename=path.join(exportDirectory,'invalid-import.ndjson');
  const fixture=[{collection:'workouts',owner:'bob',id:'w',data:row('w',{},'bob')},{collection:'workout_exercises',owner:'alice',id:'we',data:row('we',{workout_id:'w',private_test:'PRIVATE_HEALTH_VALUE'})}];
  await writeFile(filename,fixture.map(x=>JSON.stringify(x)).join('\n'));
  const execute=promisify(execFile),script=fileURLToPath(new URL('../scripts/import-records.mjs',import.meta.url));
  await assert.rejects(execute(process.execPath,[script,filename,'--apply'],{env:{PATH:process.env.PATH,MIGRATION_DATABASE_URL:process.env.TEST_ADMIN_DATABASE_URL}}),error=>!error.stderr.includes('PRIVATE_HEALTH_VALUE')&&JSON.parse(error.stderr).code==='23503');
  assert.equal((await rows('bob','workouts').get()).size,0);
});

test('owner lifecycle lock is exclusive across sessions and leaves query capacity available',async()=>{
  const {withOwnerLifecycleLock}=await import('../lib/database/postgres.js');
  let release;const held=new Promise(resolve=>{release=resolve;});let acquired;const ready=new Promise(resolve=>{acquired=resolve;});
  const first=withOwnerLifecycleLock('alice',async signal=>{await seed('weight_entries','within-lock',{weight_kg:80});acquired();await held;signal.throwIfAborted();return 'done';});
  await ready;
  try {
    await assert.rejects(withOwnerLifecycleLock('alice',async()=>{}),e=>e.status===409&&e.code==='account_busy');
    assert.equal(await withOwnerLifecycleLock('bob',async()=> (await rows('alice','weight_entries').get()).size),1);
  }finally{release();await first;}
  assert.equal(await withOwnerLifecycleLock('alice',async()=> 'released'),'released');
});
