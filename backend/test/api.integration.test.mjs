import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {mkdtemp,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
if(!process.env.FIREBASE_AUTH_EMULATOR_HOST||process.env.FIREBASE_PROJECT_ID!=='demo-leanguard')throw new Error('Use the isolated Auth-emulator HTTP runner.');
if(!process.env.TEST_DATABASE_URL||!new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test'))throw new Error('TEST_DATABASE_URL must point to a disposable *_test database.');
process.env.DATABASE_URL=process.env.TEST_DATABASE_URL;
process.env.EXPORT_SIGNING_SECRET='isolated-test-signing-secret-with-no-live-usage';
process.env.NODE_ENV='test';
const {createApp}=await import('../lib/app.js');
const {rows,auth,db}=await import('../lib/shared/platform.js');
const {exportFiles}=await import('../lib/privacy.js');
const {withOwnerLifecycleLock}=await import('../lib/database/postgres.js');
let instance,base,alice,bob,unverified,exportsDirectory;
const iso='2026-09-25T10:00:00.000Z';
const row=(identity,id,fields={})=>({id,user_id:identity.uid,created_at:iso,...fields});
async function authRequest(action,body){
  const response=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:${action}?key=fake-key`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal(response.status,200);return response.json();
}
async function user(verified=true){
  const email=`test-${crypto.randomUUID()}@example.test`,password='isolated-Test-password-121!';
  const signed=await authRequest('signUp',{email,password,returnSecureToken:true});
  if(verified)await auth.updateUser(signed.localId,{emailVerified:true});
  const result=await authRequest('signInWithPassword',{email,password,returnSecureToken:true});
  return{uid:result.localId,token:result.idToken};
}
const call=(identity,method,route,payload)=>fetch(base+route,{method,headers:{Authorization:`Bearer ${identity.token}`,...(payload?{'Content-Type':'application/json'}:{})},...(payload?{body:JSON.stringify(payload)}:{})});
const save=(identity,table,value,id=value.id)=>call(identity,'PUT',`/v1/records/${table}/${id}`,value);
before(async()=>{
  exportsDirectory=await mkdtemp(path.join(os.tmpdir(),'leanguard-api-http-'));process.env.EXPORT_DIRECTORY=exportsDirectory;
  [alice,bob,unverified]=await Promise.all([user(),user(),user(false)]);
  instance=createServer(createApp());await new Promise(resolve=>instance.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${instance.address().port}`;process.env.PUBLIC_BASE_URL=base;
});
after(async()=>{
  if(instance)await new Promise(resolve=>{instance.close(resolve);instance.closeAllConnections();});
  for(const identity of[alice,bob,unverified].filter(Boolean)){await db.recursiveDelete(db.collection('users').doc(identity.uid));await auth.deleteUser(identity.uid);}
  await db.terminate();if(exportsDirectory)await rm(exportsDirectory,{recursive:true,force:true});
});
test('real verified Firebase ID tokens authorize HTTP; unverified and malformed tokens fail',async()=>{
  assert.equal((await call(alice,'GET','/v1/records/weight_entries')).status,200);
  assert.equal((await call(unverified,'GET','/v1/records/weight_entries')).status,403);
  assert.equal((await call({token:'fake'},'GET','/v1/records/weight_entries')).status,401);
});
test('HTTP writes persist in PostgreSQL and another owner cannot see or overwrite them',async()=>{
  const value=row(alice,'weight_1',{recorded_at:iso,weight_kg:80,source:'manual'});
  assert.equal((await save(alice,'weight_entries',value)).status,200);
  const own=await(await call(alice,'GET','/v1/records/weight_entries')).json();assert.equal(own.records[0].weight_kg,80);
  assert.deepEqual(await(await call(bob,'GET','/v1/records/weight_entries')).json(),{records:[]});
  assert.equal((await save(bob,'weight_entries',value)).status,403);
  assert.equal((await save(alice,'weight_entries',{...value,server_admin:true})).status,400);
  assert.equal((await save(alice,'weight_entries',value,'wrong')).status,400);
});
test('natural-key upserts preserve the first row identity and pagination is stable',async()=>{
  const first=row(alice,'day_uuid_1',{date:'2026-09-25',steps:500,source:'manual'});
  assert.equal((await save(alice,'daily_activities',first,'2026-09-25')).status,200);
  const second=await save(alice,'daily_activities',{...first,id:'new_device_uuid',created_at:'2026-09-25T11:00:00.000Z',steps:700},'2026-09-25');
  assert.equal(second.status,200);const saved=await second.json();assert.equal(saved.id,'day_uuid_1');assert.equal(saved.created_at,iso);
  assert.equal((await call(alice,'GET','/v1/records/daily_activities?limit=501')).status,400);
  assert.equal((await call(alice,'GET','/v1/records/daily_activities?offset=1&limit=1')).status,200);
  assert.deepEqual(await(await call(alice,'GET','/v1/records/daily_activities?offset=1&limit=1')).json(),{records:[]});
});
test('server-owned records and private collections reject direct client writes',async()=>{
  for(const table of['subscription_entitlements','weekly_insights','consent_records','coach_messages'])assert.equal((await save(alice,table,row(alice,'fake'))).status,403);
  assert.equal((await call(alice,'GET','/v1/records/ai_quota')).status,404);
  assert.equal((await call(alice,'GET','/v1/records/device_tokens')).status,404);
});
test('same-owner parent references and Pro gates are enforced over HTTP',async()=>{
  const foreign=row(bob,'private_workout',{name:'Private',status:'planned'});assert.equal((await save(bob,'workouts',foreign)).status,200);
  const exercise=row(alice,'exercise',{name:'Squat',muscle_group:'Legs',equipment:'bodyweight',instructions:['Controlled movement']});assert.equal((await save(alice,'exercises',exercise)).status,200);
  const planned=row(alice,'planned_exercise',{workout_id:'private_workout',exercise_id:'exercise',position:0,target_sets:3,target_reps:8,target_weight_kg:0,rest_seconds:60,status:'planned'});
  assert.equal((await save(alice,'workout_exercises',planned)).status,400);
  const measure=row(alice,'measure',{recorded_at:iso,chest_cm:100});assert.equal((await save(alice,'body_measurements',measure)).status,403);
  await rows(alice.uid,'subscription_entitlements').doc('pro').set(row(alice,'entitlement',{entitlement_id:'pro',is_active:true,access_until_ms:Date.now()+60000}));
  assert.equal((await save(alice,'body_measurements',measure)).status,200);
  await rows(alice.uid,'subscription_entitlements').doc('pro').update({is_active:false});
  assert.equal((await call(alice,'GET','/v1/records/body_measurements')).status,200);
  assert.equal((await save(alice,'body_measurements',{...measure,chest_cm:99})).status,403);
});
test('specialized FCM route uses server ownership and stable token identity',async()=>{
  const payload={token:'local-test-fcm-token-longer-than-twenty-characters',platform:'ios'};
  const first=await call(alice,'PUT','/v1/device-tokens',payload);assert.equal(first.status,200);const saved=await first.json();assert.match(saved.id,/^[a-f0-9]{64}$/);assert.equal(saved.user_id,alice.uid);
  const second=await(await call(alice,'PUT','/v1/device-tokens',payload)).json();assert.equal(second.created_at,saved.created_at);
  assert.equal((await call(bob,'DELETE',`/v1/device-tokens/${saved.id}`)).status,200);assert.equal((await rows(alice.uid,'device_tokens').doc(saved.id).get()).exists,true);
  assert.equal((await call(alice,'DELETE',`/v1/device-tokens/${saved.id}`)).status,200);assert.equal((await rows(alice.uid,'device_tokens').doc(saved.id).get()).exists,false);
});
test('consent and raw export work through authenticated actions without paid providers',async()=>{
  const consent=row(alice,crypto.randomUUID(),{kind:'health_data',granted:true,policy_version:'test'});
  assert.equal((await call(alice,'POST','/v1/recordConsent',{row:consent})).status,200);
  const exported=await call(alice,'POST','/v1/dataExport',{});assert.equal(exported.status,200);const body=await exported.json();assert.equal(body.user_id,alice.uid);assert.equal(body.tables.weight_entries[0].weight_kg,80);
  assert.equal((await call(alice,'POST','/v1/dataExport',{})).status,429);
});
test('private download requires valid owner-bound signature and no bearer token',async()=>{
  const files=exportFiles(),output=await files.create(alice.uid);await output.write('{"test":true}');await output.finish();
  const signed=files.signedUrl(alice.uid,output.name);
  const response=await fetch(signed);assert.equal(response.status,200);assert.deepEqual(await response.json(),{test:true});
  assert.equal((await fetch(signed.replace(alice.uid,bob.uid))).status,404);
  const tampered=new URL(signed);tampered.searchParams.set('signature','0'.repeat(64));assert.equal((await fetch(tampered)).status,404);
});
test('concurrent Free starter creation admits one canonical plan and preserves workout logging',async()=>{
  const fields={name:'Muscle retention foundation',description:'A starter 3-day plan. Start with a comfortable load and controlled repetitions.',source:'starter',version:1,is_active:true,schedule:[{day:1,name:'Lower body'},{day:4,name:'Upper body'},{day:6,name:'Full body'}]};
  const results=await Promise.all([1,2,3].map(i=>save(alice,'strength_plans',row(alice,`starter_${i}`,fields))));
  assert.deepEqual(results.map(r=>r.status).sort(),[200,403,403]);
  assert.equal((await save(alice,'strength_plans',row(alice,'arbitrary',{...fields,name:'Custom bypass'}))).status,403);
  const plans=await(await call(alice,'GET','/v1/records/strength_plans')).json();assert.equal(plans.records.length,1);
  const plan=plans.records[0];assert.equal((await save(alice,'strength_plans',{...plan,version:2,schedule:[{day:1},{day:4},{day:6}]})).status,200);
  assert.equal((await save(alice,'workouts',row(alice,'free_completed',{plan_id:plan.id,name:'Lower body',status:'completed',duration_seconds:600,completed_at:iso}))).status,200);
});
test('account deletion waits for owner privacy work then removes Auth, PostgreSQL and private exports',async()=>{
  const account=await user();
  try{
    await save(account,'weight_entries',row(account,'weight',{weight_kg:75,recorded_at:iso,source:'manual'}));
    const files=exportFiles(),output=await files.create(account.uid);await output.write('{"private":true}');await output.finish();const signed=files.signedUrl(account.uid,output.name);
    let release,entered;const started=new Promise(resolve=>{entered=resolve;});const gate=new Promise(resolve=>{release=resolve;});
    const lock=withOwnerLifecycleLock(account.uid,async()=>{entered();await gate;});await started;
    const blocked=await call(account,'POST','/v1/deleteAccount',{confirmation:'DELETE'});assert.equal(blocked.status,409);
    assert.equal((await auth.getUser(account.uid)).uid,account.uid);assert.equal((await rows(account.uid,'weight_entries').doc('weight').get()).exists,true);release();await lock;
    const realFetch=globalThis.fetch;
    globalThis.fetch=async(input,options)=>String(input).startsWith('https://api.revenuecat.com/v1/subscribers/')&&options?.method==='DELETE'?new Response('',{status:200}):realFetch(input,options);
    try{const deleted=await call(account,'POST','/v1/deleteAccount',{confirmation:'DELETE'});assert.equal(deleted.status,200);assert.equal((await deleted.json()).deleted,true);}
    finally{globalThis.fetch=realFetch;}
    await assert.rejects(auth.getUser(account.uid),{code:'auth/user-not-found'});
    assert.equal((await rows(account.uid,'weight_entries').get()).size,0);assert.equal((await fetch(signed)).status,404);
    await assert.rejects(files.read(account.uid,output.name));
  }finally{
    await auth.deleteUser(account.uid).catch(()=>{});await db.recursiveDelete(db.collection('users').doc(account.uid));await db.collection('account_deletions').doc(account.uid).delete();
  }
});
