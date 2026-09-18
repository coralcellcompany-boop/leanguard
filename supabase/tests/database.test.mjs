import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Embedded PostgreSQL executes the actual migrations and policies. The minimal
// auth/storage scaffolding below replaces services owned by Supabase itself.
// pgcrypto is omitted because gen_random_uuid is built into this PostgreSQL.
const db = new PGlite();
const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
const plan = '33333333-3333-4333-8333-333333333333';
const workout = '44444444-4444-4444-8444-444444444444';
const exercise = '55555555-5555-4555-8555-555555555555';
const we = '66666666-6666-4666-8666-666666666666';
const proposal = '77777777-7777-4777-8777-777777777777';

before(async () => {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema storage; create schema extensions;
    create table auth.users(id uuid primary key,email text);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;
    create function storage.foldername(name text) returns text[] language sql immutable as $$select string_to_array(name,'/')$$;
    grant usage on schema public,auth,storage to anon,authenticated,service_role;
    grant all on storage.objects to authenticated;
  `);
  const directory = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(directory)).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = (await readFile(new URL(file, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', '');
    await db.exec(sql);
  }
  await db.query('insert into auth.users(id,email) values($1,$2),($3,$4)', [a, 'a@example.test', b, 'b@example.test']);
});
after(async () => { await db.close(); });

async function asUser(user, sql, params = []) {
  await db.exec('begin; set local role authenticated;');
  await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
  try {
    const result = await db.query(sql, params);
    await db.exec('commit');
    return result;
  } catch (error) { await db.exec('rollback'); throw error; }
}

test('RLS isolates reads, rejects another owner and disallows changing ownership', async () => {
  await asUser(a, 'insert into user_profiles(user_id,display_name) values($1,$2)', [a, 'Alex']);
  await asUser(b, 'insert into user_profiles(user_id,display_name) values($1,$2)', [b, 'Bea']);
  const own = await asUser(a, 'select display_name from user_profiles');
  assert.deepEqual(own.rows.map((x) => x.display_name), ['Alex']);
  await assert.rejects(asUser(a, 'insert into weight_entries(user_id,weight_kg) values($1,80)', [b]), (e) => e.code === '42501');
  await assert.rejects(asUser(a, 'update user_profiles set user_id=$1 where user_id=$2', [b, a]), (e) => e.code === '42501');
});
test('composite parent keys reject cross-user workout relationships', async () => {
  await asUser(a, 'insert into strength_plans(id,user_id,name) values($1,$2,$3)', [plan, a, 'Starter']);
  await assert.rejects(asUser(b, 'insert into workouts(user_id,plan_id,name) values($1,$2,$3)', [b, plan, 'Stolen parent']), (e) => e.code === '23503');
  await asUser(a, 'insert into workouts(id,user_id,plan_id,name) values($1,$2,$3,$4)', [workout, a, plan, 'Session A']);
  await asUser(a, 'insert into exercises(id,user_id,name) values($1,$2,$3)', [exercise, a, 'Squat']);
  await asUser(a, 'insert into workout_exercises(id,user_id,workout_id,exercise_id,target_weight_kg) values($1,$2,$3,$4,50)', [we, a, workout, exercise]);
  await assert.rejects(asUser(b, 'insert into workout_sets(user_id,workout_exercise_id,set_number,reps) values($1,$2,1,10)', [b, we]), (e) => e.code === '23503');
});
test('entitlements and server-owned AI records cannot be forged', async () => {
  await assert.rejects(asUser(a, 'insert into subscription_entitlements(user_id,is_active) values($1,true)', [a]), (e) => e.code === '42501');
  await assert.rejects(asUser(a, 'select reserve_ai_request($1,$2,$3)', [a, 'question', 'a'.repeat(64)]), (e) => e.code === '42501');
  await assert.rejects(asUser(a, 'insert into weekly_insights(user_id,week_start,snapshot_hash,prompt_version,content) values($1,current_date,$2,$3,$4)', [a, 'hash', 'v1', '{}']), (e) => e.code === '42501');
});
test('free quota is three questions a month plus one weekly summary', async () => {
  for (let i = 0; i < 3; i++) {
    const result = await db.query('select reserve_ai_request($1,$2,$3) as value', [a, 'question', String(i).repeat(64)]);
    assert.equal(result.rows[0].value.status, 'reserved');
  }
  const exhausted = await db.query('select reserve_ai_request($1,$2,$3) as value', [a, 'question', 'x'.repeat(64)]);
  assert.equal(exhausted.rows[0].value.status, 'quota_exceeded');
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [a, 'weekly', 'w'.repeat(64)])).rows[0].value.status, 'reserved');
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [a, 'weekly', 'z'.repeat(64)])).rows[0].value.status, 'quota_exceeded');
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [a, 'adaptation', 'y'.repeat(64)])).rows[0].value.status, 'pro_required');
});
test('identical in-flight requests cannot reserve twice and cache avoids charging', async () => {
  const hash = 'b'.repeat(64);
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [b, 'question', hash])).rows[0].value.status, 'reserved');
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [b, 'question', hash])).rows[0].value.status, 'in_progress');
  await db.query("insert into ai_cache(user_id,cache_key,result,expires_at) values($1,$2,'{\"summary\":\"cached\"}',now()+interval '1 day')", [b, hash]);
  assert.equal((await db.query('select reserve_ai_request($1,$2,$3) as value', [b, 'question', hash])).rows[0].value.status, 'cached');
  assert.equal((await db.query('select count(*)::int as n from ai_requests where user_id=$1', [b])).rows[0].n, 1);
});
test('free reminder and measurement writes are constrained', async () => {
  for (let i = 0; i < 3; i++) await asUser(a, 'insert into reminder_preferences(user_id,kind,title) values($1,$2,$3)', [a, 'walking', `Walk ${i}`]);
  await assert.rejects(asUser(a, 'insert into reminder_preferences(user_id,kind,title) values($1,$2,$3)', [a, 'protein', 'Fourth reminder']), /up to three/);
  await assert.rejects(asUser(a, 'insert into reminder_preferences(user_id,kind,title,smart) values($1,$2,$3,true)', [a, 'walking', 'Smart']), /Pro required/);
  await asUser(a, 'insert into body_measurements(user_id,waist_cm) values($1,90)', [a]);
  await assert.rejects(asUser(a, 'insert into body_measurements(user_id,chest_cm) values($1,100)', [a]), /Pro required/);
});
test('consent is append-only and Pro expiry never hides existing data', async () => {
  await asUser(a, 'insert into consent_records(user_id,kind,granted,policy_version) values($1,$2,true,$3)', [a, 'ai_processing', 'v1']);
  await assert.rejects(asUser(a, 'update consent_records set granted=false where user_id=$1', [a]), (e) => e.code === '42501');
  await db.query("insert into subscription_entitlements(user_id,is_active,expires_at) values($1,true,now()+interval '1 day')", [a]);
  await asUser(a, 'insert into body_measurements(user_id,chest_cm) values($1,100)', [a]);
  await db.query("update subscription_entitlements set expires_at=now()-interval '1 day' where user_id=$1", [a]);
  assert.equal((await asUser(a, 'select chest_cm from body_measurements where chest_cm is not null')).rows.length, 1);
  assert.equal((await db.query('select user_has_pro($1) as value', [a])).rows[0].value, false);
});
test('plan approval requires ownership, active Pro, current version, explicit approval, and bounded changes', async () => {
  await db.query("update subscription_entitlements set expires_at=now()+interval '1 day' where user_id=$1", [a]);
  const changes = JSON.stringify([{ workout_exercise_id: we, target_weight_kg: 52.5, target_reps: 10, target_sets: 3 }]);
  await db.query('insert into plan_proposals(id,user_id,plan_id,plan_version,rationale,changes) values($1,$2,$3,1,$4,$5)', [proposal, a, plan, 'Repeated comfortable sessions.', changes]);
  assert.equal((await db.query('select target_weight_kg from workout_exercises where id=$1', [we])).rows[0].target_weight_kg, '50.00');
  await assert.rejects(asUser(b, 'select approve_plan_proposal($1,true)', [proposal]), /Proposal not found/);
  const approved = await asUser(a, 'select approve_plan_proposal($1,true) as value', [proposal]);
  assert.equal(approved.rows[0].value.state, 'approved');
  assert.equal((await db.query('select target_weight_kg from workout_exercises where id=$1', [we])).rows[0].target_weight_kg, '52.50');
  assert.equal((await asUser(a, 'select approve_plan_proposal($1,true) as value', [proposal])).rows[0].value.state, 'approved');
  assert.equal((await db.query('select version from strength_plans where id=$1', [plan])).rows[0].version, 2);
});
test('out-of-order RevenueCat responses cannot roll back verified entitlement', async () => {
  const active = JSON.stringify({ is_active: true, product_id: 'annual', expires_at: '2030-01-01', grace_period_expires_at: null, status: 'active', will_renew: true, management_url: null, is_sandbox: false });
  const expired = JSON.stringify({ is_active: false, product_id: 'annual', expires_at: '2026-01-01', grace_period_expires_at: null, status: 'expired', will_renew: false, management_url: null, is_sandbox: false });
  await db.query('select reconcile_entitlement($1,$2,$3)', [a, active, '2029-01-01']);
  await db.query('select reconcile_entitlement($1,$2,$3)', [a, expired, '2028-01-01']);
  assert.equal((await db.query('select is_active from subscription_entitlements where user_id=$1', [a])).rows[0].is_active, true);
});
test('private storage only exposes files in the caller UUID directory', async () => {
  await asUser(a, "insert into storage.objects(bucket_id,name) values('avatars',$1)", [`${a}/avatar.png`]);
  assert.equal((await asUser(b, "select * from storage.objects where bucket_id='avatars'")).rows.length, 0);
  await assert.rejects(asUser(b, "insert into storage.objects(bucket_id,name) values('avatars',$1)", [`${a}/stolen.png`]), (e) => e.code === '42501');
});
test('background health import requires consent and Pro while preserving manual activity', async () => {
  await assert.rejects(asUser(a, "select sync_health_activity(current_date,6000,150,'apple_health')"), /Health permission required/);
  await asUser(a, "insert into consent_records(user_id,kind,granted,policy_version) values($1,'health_data',true,'v1')", [a]);
  await asUser(a, "insert into health_connections(user_id,provider,status) values($1,'apple_health','connected')", [a]);
  assert.equal((await asUser(a, "select sync_health_activity(current_date,6000,150,'apple_health') as value")).rows[0].value.synced, true);
  await asUser(a, "select sync_health_activity(current_date,6200,null,'apple_health')");
  assert.equal((await asUser(a, 'select active_energy_kcal from daily_activities where date=current_date')).rows[0].active_energy_kcal, '150.00');
  await asUser(a, "update daily_activities set steps=8000,source='manual' where user_id=$1 and date=current_date", [a]);
  assert.equal((await asUser(a, "select sync_health_activity(current_date,6500,160,'apple_health') as value")).rows[0].value.preserved_manual, true);
  assert.equal((await asUser(a, 'select steps from daily_activities where date=current_date')).rows[0].steps, 8000);
  await assert.rejects(asUser(b, "select sync_health_activity(current_date,6000,150,'health_connect')"), /Pro required/);
});
test('account deletion cascades through owned health and coaching records', async () => {
  await db.query('delete from auth.users where id=$1', [a]);
  for (const table of ['user_profiles', 'workouts', 'workout_exercises', 'plan_proposals', 'body_measurements', 'consent_records', 'subscription_entitlements', 'ai_requests']) {
    assert.equal((await db.query(`select count(*)::int as n from ${table} where user_id=$1`, [a])).rows[0].n, 0, table);
  }
});
