-- A single lock per user makes quota reservations atomic across function
-- instances; client-supplied counters or plan flags are never accepted.
create function public.reserve_ai_request(p_user_id uuid,p_kind text,p_cache_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  pro boolean; used_count integer; allowance integer; request_id uuid; cached jsonb;
  month_start timestamptz := date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
  week_start timestamptz := date_trunc('week',now() at time zone 'UTC') at time zone 'UTC';
begin
  if p_kind not in ('question','weekly','adaptation') or length(p_cache_key)<>64 then
    raise exception 'Invalid request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,19));
  pro := public.user_has_pro(p_user_id);
  if p_kind='adaptation' and not pro then return jsonb_build_object('status','pro_required'); end if;
  if (select count(*) from public.ai_requests where user_id=p_user_id and created_at>now()-interval '1 minute')>=6 then
    return jsonb_build_object('status','rate_limited','retry_after',60);
  end if;
  select result into cached from public.ai_cache where user_id=p_user_id and cache_key=p_cache_key and expires_at>now();
  if cached is not null then return jsonb_build_object('status','cached','result',cached); end if;
  if exists(select 1 from public.ai_requests where user_id=p_user_id and cache_key=p_cache_key and state='reserved' and created_at>now()-interval '1 minute') then
    return jsonb_build_object('status','in_progress','retry_after',10);
  end if;
  -- Abandoned function executions no longer consume a monthly allowance.
  update public.ai_requests set state='failed' where user_id=p_user_id and state='reserved' and created_at<now()-interval '1 minute';
  if not pro and p_kind='weekly' then
    allowance := 1;
    select count(*) into used_count from public.ai_requests where user_id=p_user_id and kind='weekly' and state<>'failed' and created_at>=week_start;
  else
    allowance := case when pro then 100 else 3 end;
    select count(*) into used_count from public.ai_requests where user_id=p_user_id and state<>'failed' and created_at>=month_start and (pro or kind='question');
  end if;
  if used_count>=allowance then return jsonb_build_object('status','quota_exceeded','limit',allowance,'used',used_count); end if;
  if pro and (select count(*) from public.ai_requests where user_id=p_user_id and state<>'failed' and created_at>=now()-interval '24 hours')>=20 then
    return jsonb_build_object('status','fair_use_limit','retry_after',3600);
  end if;
  insert into public.ai_requests(user_id,kind,cache_key) values(p_user_id,p_kind,p_cache_key) returning id into request_id;
  return jsonb_build_object('status','reserved','request_id',request_id,'is_pro',pro,'remaining',allowance-used_count-1);
end $$;
revoke all on function public.reserve_ai_request(uuid,text,text) from public,anon,authenticated;
grant execute on function public.reserve_ai_request(uuid,text,text) to service_role;

create function public.approve_plan_proposal(p_proposal_id uuid,p_approved boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  proposal public.plan_proposals; plan public.strength_plans;
  item jsonb; exercise public.workout_exercises;
  new_weight numeric; new_reps integer; new_sets integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into proposal from public.plan_proposals where id=p_proposal_id and user_id=auth.uid() for update;
  if not found then raise exception 'Proposal not found'; end if;
  if proposal.state<>'pending' then return jsonb_build_object('state',proposal.state,'proposal_id',proposal.id); end if;
  if not p_approved then
    update public.plan_proposals set state='rejected' where id=proposal.id;
    return jsonb_build_object('state','rejected','proposal_id',proposal.id);
  end if;
  if proposal.expires_at<=now() then raise exception 'Proposal expired'; end if;
  if not public.user_has_pro(auth.uid()) then raise exception 'Pro required'; end if;
  select * into plan from public.strength_plans where id=proposal.plan_id and user_id=auth.uid() for update;
  if not found or not plan.is_active or plan.version<>proposal.plan_version then
    raise exception 'Plan changed; request a fresh proposal';
  end if;
  for item in select * from jsonb_array_elements(proposal.changes) loop
    select we.* into exercise from public.workout_exercises we
      join public.workouts w on w.id=we.workout_id and w.user_id=we.user_id
      where we.id=(item->>'workout_exercise_id')::uuid and we.user_id=auth.uid()
      and w.plan_id=plan.id and w.status='planned' for update of we;
    if not found then raise exception 'Only unstarted workouts can be adapted'; end if;
    new_weight := coalesce((item->>'target_weight_kg')::numeric,exercise.target_weight_kg);
    new_reps := coalesce((item->>'target_reps')::integer,exercise.target_reps);
    new_sets := coalesce((item->>'target_sets')::integer,exercise.target_sets);
    if new_weight<exercise.target_weight_kg*0.8 or new_weight>exercise.target_weight_kg*1.05
      or abs(new_reps-exercise.target_reps)>2 or abs(new_sets-exercise.target_sets)>1
      or new_reps not between 1 and 30 or new_sets not between 1 and 6
      or (new_weight>exercise.target_weight_kg and (new_reps>exercise.target_reps or new_sets>exercise.target_sets))
      or (new_reps>exercise.target_reps and new_sets>exercise.target_sets) then
      raise exception 'Proposal exceeds conservative progression bounds';
    end if;
    update public.workout_exercises set target_weight_kg=new_weight,target_reps=new_reps,target_sets=new_sets where id=exercise.id;
  end loop;
  update public.strength_plans set version=version+1 where id=plan.id;
  update public.plan_proposals set state='approved',approved_at=now() where id=proposal.id;
  return jsonb_build_object('state','approved','proposal_id',proposal.id,'plan_id',plan.id,'version',plan.version+1);
end $$;
revoke all on function public.approve_plan_proposal(uuid,boolean) from public,anon;
grant execute on function public.approve_plan_proposal(uuid,boolean) to authenticated;

create function public.claim_notification_deliveries(p_limit integer default 100)
returns setof public.notification_deliveries language plpgsql security definer set search_path = '' as $$
begin
  return query with claimed as (
    select id from public.notification_deliveries
      where (state in ('pending','failed') or (state='sending' and leased_until<now())) and attempts<5
      order by created_at limit least(greatest(p_limit,1),500) for update skip locked
  ) update public.notification_deliveries d set state='sending',attempts=attempts+1,leased_until=now()+interval '2 minutes'
    from claimed where d.id=claimed.id returning d.*;
end $$;
revoke all on function public.claim_notification_deliveries(integer) from public,anon,authenticated;
grant execute on function public.claim_notification_deliveries(integer) to service_role;

-- Validate IANA time zones before they reach the scheduler.
create function public.validate_time_zone() returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists(select 1 from pg_timezone_names where name=new.time_zone) then raise exception 'Invalid time zone'; end if;
  return new;
end $$;
create trigger profile_timezone before insert or update on public.user_profiles for each row execute function public.validate_time_zone();
create trigger reminder_timezone before insert or update on public.reminder_preferences for each row execute function public.validate_time_zone();

-- Revoke execution on trigger functions too: no accidental public RPCs.
revoke all on function public.touch_updated_at(),public.enforce_plan_limits(),public.validate_time_zone() from public,anon,authenticated;
