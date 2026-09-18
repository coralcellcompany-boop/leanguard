-- All timestamps are UTC. Metric units are canonical on the server.
create extension if not exists pgcrypto with schema extensions;

create table public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  display_name text not null default '' check (length(display_name) <= 80),
  units text not null default 'metric' check (units in ('metric','imperial')),
  time_zone text not null default 'UTC',
  onboarding_completed boolean not null default false,
  analytics_enabled boolean not null default false,
  crash_reporting_enabled boolean not null default false,
  coaching_tone text not null default 'supportive',
  avatar_path text,
  unique(id,user_id)
);

create table public.goal_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  goals text[] not null default '{}',
  goal text not null default 'lose_weight' check (goal in ('lose_weight','build_strength','stay_consistent')),
  target_weight_kg numeric(6,2) check(target_weight_kg between 20 and 500),
  workouts_per_week integer not null default 3 check(workouts_per_week between 1 and 7),
  protein_target_g integer not null default 120 check(protein_target_g between 20 and 400),
  step_target integer not null default 7000 check(step_target between 500 and 50000),
  equipment text[] not null default '{}',
  dietary_preferences text[] not null default '{}',
  allergies text[] not null default '{}',
  limitations text[] not null default '{}',
  exercise_preferences text[] not null default '{}',
  session_minutes integer not null default 35 check(session_minutes between 10 and 180),
  training_days integer[] not null default '{1,3,5}' check(training_days <@ array[1,2,3,4,5,6,7]),
  unique(id,user_id)
);

create table public.health_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  provider text not null check(provider in ('apple_health','health_connect')),
  status text not null default 'disconnected' check(status in ('connected','disconnected','denied','unavailable')),
  permissions text[] not null default '{}',
  last_synced_at timestamptz,
  unique(user_id,provider), unique(id,user_id)
);

create table public.medication_support_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  enabled boolean not null default false,
  clinician_supervised boolean not null default false,
  appetite_level text not null default 'normal' check(appetite_level in ('normal','low','very_low')),
  hydration_reminders boolean not null default false,
  check_ins_enabled boolean not null default false,
  check(not enabled or clinician_supervised), unique(id,user_id)
);

create table public.strength_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null check(length(name) between 1 and 120),
  description text not null default '',
  is_active boolean not null default true,
  version integer not null default 1 check(version > 0),
  source text not null default 'starter' check(source in ('starter','manual','coach')),
  schedule jsonb not null default '[]' check(jsonb_typeof(schedule) = 'array'),
  unique(id,user_id)
);
create unique index one_active_plan on public.strength_plans(user_id) where is_active;

create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  name text not null check(length(name) between 1 and 120),
  muscle_group text not null default 'full_body',
  equipment text not null default 'bodyweight',
  instructions text[] not null default '{}',
  image_url text,
  unique(id,user_id)
);

create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  plan_id uuid,
  name text not null check(length(name) between 1 and 120),
  status text not null default 'planned' check(status in ('planned','in_progress','completed','skipped')),
  scheduled_date date,
  started_at timestamptz,
  completed_at timestamptz,
  duration_seconds integer not null default 0 check(duration_seconds between 0 and 86400),
  notes text not null default '' check(length(notes) <= 2000),
  unique(id,user_id),
  foreign key(plan_id,user_id) references public.strength_plans(id,user_id) on delete cascade
);

create table public.workout_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  workout_id uuid not null,
  exercise_id uuid not null,
  position integer not null default 0 check(position between 0 and 100),
  target_sets integer not null default 3 check(target_sets between 1 and 20),
  target_reps integer not null default 10 check(target_reps between 1 and 100),
  target_weight_kg numeric(7,2) not null default 0 check(target_weight_kg between 0 and 1000),
  rest_seconds integer not null default 90 check(rest_seconds between 0 and 600),
  status text not null default 'planned' check(status in ('planned','completed','skipped')),
  unique(id,user_id), unique(workout_id,position),
  foreign key(workout_id,user_id) references public.workouts(id,user_id) on delete cascade,
  foreign key(exercise_id,user_id) references public.exercises(id,user_id) on delete cascade
);

create table public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  workout_exercise_id uuid not null,
  set_number integer not null check(set_number between 1 and 100),
  reps integer not null check(reps between 0 and 200),
  weight_kg numeric(7,2) not null default 0 check(weight_kg between 0 and 1000),
  completed boolean not null default true,
  completed_at timestamptz,
  rpe numeric(3,1) check(rpe between 1 and 10),
  unique(id,user_id), unique(workout_exercise_id,set_number),
  foreign key(workout_exercise_id,user_id) references public.workout_exercises(id,user_id) on delete cascade
);

create table public.daily_targets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  date date not null default current_date,
  steps integer not null default 7000 check(steps between 500 and 50000),
  protein_g integer not null default 120 check(protein_g between 20 and 400),
  unique(user_id,date), unique(id,user_id)
);

create table public.daily_activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  date date not null default current_date,
  steps integer not null default 0 check(steps between 0 and 200000),
  active_energy_kcal numeric(8,2) not null default 0 check(active_energy_kcal between 0 and 50000),
  readiness_score integer check(readiness_score between 0 and 100),
  energy_level integer check(energy_level between 1 and 5),
  source text not null default 'manual' check(source in ('manual','apple_health','health_connect')),
  unique(user_id,date), unique(id,user_id)
);

create table public.protein_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  name text not null check(length(name) between 1 and 200),
  protein_g numeric(6,1) not null check(protein_g > 0 and protein_g <= 300),
  meal_type text not null default 'snack' check(meal_type in ('breakfast','lunch','dinner','snack')),
  unique(id,user_id)
);

create table public.weight_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  weight_kg numeric(6,2) not null check(weight_kg between 20 and 500),
  source text not null default 'manual' check(source in ('manual','apple_health','health_connect')),
  external_id text,
  unique(user_id,source,external_id), unique(id,user_id)
);

create table public.body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  waist_cm numeric(5,1) check(waist_cm between 20 and 300),
  chest_cm numeric(5,1) check(chest_cm between 20 and 300),
  hips_cm numeric(5,1) check(hips_cm between 20 and 300),
  arm_cm numeric(5,1) check(arm_cm between 10 and 100),
  thigh_cm numeric(5,1) check(thigh_cm between 10 and 150),
  check(num_nonnulls(waist_cm,chest_cm,hips_cm,arm_cm,thigh_cm) > 0),
  unique(id,user_id)
);

create table public.weekly_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  week_start date not null,
  snapshot_hash text not null,
  prompt_version text not null,
  content jsonb not null,
  unique(user_id,week_start,snapshot_hash,prompt_version), unique(id,user_id)
);

create table public.coach_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  title text not null default 'Lean Coach' check(length(title) <= 120),
  unique(id,user_id)
);
create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  conversation_id uuid not null,
  role text not null check(role in ('user','assistant')),
  content text not null check(length(content) <= 10000),
  structured_content jsonb,
  safety_classification text,
  prompt_version text,
  unique(id,user_id),
  foreign key(conversation_id,user_id) references public.coach_conversations(id,user_id) on delete cascade
);

create table public.reminder_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  kind text not null check(kind in ('workout','protein','walking','weight','hydration','check_in','weekly')),
  title text not null check(length(title) between 1 and 100),
  time_of_day time not null default '09:00',
  days_of_week integer[] not null default '{1,2,3,4,5,6,7}' check(days_of_week <@ array[1,2,3,4,5,6,7]),
  enabled boolean not null default true,
  smart boolean not null default false,
  quiet_start time,
  quiet_end time,
  time_zone text not null default 'UTC',
  delivery text not null default 'local' check(delivery in ('local','push')),
  check((quiet_start is null) = (quiet_end is null)), unique(id,user_id)
);

create table public.subscription_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  entitlement_id text not null default 'pro' check(entitlement_id = 'pro'),
  is_active boolean not null default false,
  product_id text,
  expires_at timestamptz,
  grace_period_expires_at timestamptz,
  status text not null default 'expired' check(status in ('active','trial','cancelled','grace_period','billing_issue','expired','paused')),
  will_renew boolean not null default false,
  management_url text,
  is_sandbox boolean not null default false,
  verified_at timestamptz not null default now(),
  unique(user_id,entitlement_id), unique(id,user_id)
);

create table public.consent_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  kind text not null check(kind in ('terms','privacy','health_data','ai_processing','analytics','crash_reporting','notifications')),
  granted boolean not null,
  policy_version text not null check(length(policy_version) between 1 and 40),
  unique(id,user_id)
);

create table public.plan_proposals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  plan_id uuid not null,
  plan_version integer not null,
  changes jsonb not null check(jsonb_typeof(changes)='array' and jsonb_array_length(changes) between 1 and 6),
  rationale text not null,
  state text not null default 'pending' check(state in ('pending','approved','rejected','expired')),
  expires_at timestamptz not null default now() + interval '7 days',
  approved_at timestamptz,
  unique(id,user_id),
  foreign key(plan_id,user_id) references public.strength_plans(id,user_id) on delete cascade
);

create table public.ai_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  kind text not null check(kind in ('question','weekly','adaptation')),
  cache_key text not null,
  state text not null default 'reserved' check(state in ('reserved','completed','failed')),
  unique(id,user_id)
);
create index ai_quota_idx on public.ai_requests(user_id,created_at,state);
create table public.ai_cache (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  cache_key text not null,
  result jsonb not null,
  expires_at timestamptz not null,
  unique(user_id,cache_key), unique(id,user_id)
);
create table public.revenuecat_events (
  id text primary key,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  event_type text not null
);
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  token text not null unique check(length(token) between 20 and 4096),
  platform text not null check(platform in ('ios','android')),
  unique(user_id,token), unique(id,user_id)
);
create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  reminder_id uuid not null,
  local_date date not null,
  state text not null default 'pending' check(state in ('pending','sending','sent','failed','suppressed')),
  attempts integer not null default 0,
  leased_until timestamptz,
  sent_at timestamptz,
  unique(reminder_id,local_date), unique(id,user_id),
  foreign key(reminder_id,user_id) references public.reminder_preferences(id,user_id) on delete cascade
);

-- Ownership checks remain in force for UPDATE's old AND new row. Composite
-- foreign keys prevent attaching a row to another user's parent even under RLS.
do $$
declare t text;
begin
  foreach t in array array['user_profiles','goal_profiles','health_connections','medication_support_preferences',
    'strength_plans','exercises','workouts','workout_exercises','workout_sets','daily_targets','daily_activities',
    'protein_entries','weight_entries','body_measurements','reminder_preferences','coach_conversations','device_tokens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy own_rows on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',t);
    execute format('grant select, insert, update, delete on public.%I to authenticated',t);
  end loop;
  foreach t in array array['weekly_insights','coach_messages','subscription_entitlements','plan_proposals','ai_requests','ai_cache','notification_deliveries','consent_records'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('create policy own_read on public.%I for select to authenticated using (user_id = (select auth.uid()))',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
  -- Append-only consent audit, including revocation as a new record.
  grant insert on public.consent_records to authenticated;
  create policy own_consent_insert on public.consent_records for insert to authenticated with check(user_id = (select auth.uid()));
  alter table public.revenuecat_events enable row level security;
  revoke all on public.revenuecat_events from anon,authenticated;
  grant all on all tables in schema public to service_role;
  foreach t in array array['workouts','workout_exercises','workout_sets','protein_entries','weight_entries','body_measurements','coach_messages','reminder_preferences','consent_records','notification_deliveries'] loop
    execute format('create index %I on public.%I(user_id,created_at desc)',t || '_owner_time',t);
  end loop;
end $$;

create function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
create trigger user_profile_timestamp before update on public.user_profiles for each row execute function public.touch_updated_at();
create trigger goal_profile_timestamp before update on public.goal_profiles for each row execute function public.touch_updated_at();
create trigger strength_plan_timestamp before update on public.strength_plans for each row execute function public.touch_updated_at();

create function public.user_has_pro(p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.subscription_entitlements where user_id=p_user_id and entitlement_id='pro' and is_active
  and (expires_at is null or greatest(expires_at,grace_period_expires_at)>now())
  and (not is_sandbox or current_setting('app.settings.allow_sandbox_entitlements',true)='true'));
$$;
revoke all on function public.user_has_pro(uuid) from public,anon,authenticated;
grant execute on function public.user_has_pro(uuid) to service_role;

-- Server validates feature writes, while existing rows ALWAYS remain readable
-- after expiration. Advanced measurement fields can still be cleared/deleted.
create function public.enforce_plan_limits() returns trigger
language plpgsql security definer set search_path = '' as $$
declare advanced_changed boolean;
begin
  if public.user_has_pro(new.user_id) or current_user='service_role' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 7));
  if tg_table_name='reminder_preferences' then
    if new.enabled and (new.smart or new.quiet_start is not null) then
      raise exception 'Pro required for smart reminders and quiet hours' using errcode='P0001';
    end if;
    if new.enabled and (select count(*) from public.reminder_preferences where user_id=new.user_id and enabled and id<>new.id)>=3 then
      raise exception 'Free supports up to three enabled reminders' using errcode='P0001';
    end if;
  elsif tg_table_name='body_measurements' then
    advanced_changed := num_nonnulls(new.chest_cm,new.hips_cm,new.arm_cm,new.thigh_cm)>0;
    if tg_op='UPDATE' then
      advanced_changed := advanced_changed and (new.chest_cm,new.hips_cm,new.arm_cm,new.thigh_cm) is distinct from (old.chest_cm,old.hips_cm,old.arm_cm,old.thigh_cm);
    end if;
    if advanced_changed then raise exception 'Pro required for additional body measurements' using errcode='P0001'; end if;
  end if;
  return new;
end $$;
create trigger reminder_limits before insert or update on public.reminder_preferences for each row execute function public.enforce_plan_limits();
create trigger measurement_limits before insert or update on public.body_measurements for each row execute function public.enforce_plan_limits();

-- Storage is private. Client uploads are confined to their UUID directory.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp']),
       ('exports','exports',false,10485760,array['application/json','text/csv','application/pdf'])
on conflict(id) do nothing;
create policy own_avatar_read on storage.objects for select to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy own_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy own_avatar_update on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy own_avatar_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy own_export_read on storage.objects for select to authenticated using(bucket_id='exports' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Privacy-safe aggregates only; no analytics table accepts weight, meals,
-- messages, symptoms, email addresses, or health identifiers.
