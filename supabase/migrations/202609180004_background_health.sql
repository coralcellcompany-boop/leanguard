-- Background refresh is Pro-only. This RPC preserves manually entered activity
-- even when a foreground edit races with a background import.
create function public.sync_health_activity(p_date date,p_steps integer,p_active_energy numeric,p_source text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); changed integer;
begin
  if owner_id is null then raise exception 'Authentication required'; end if;
  if p_source not in ('apple_health','health_connect') or p_steps not between 0 and 200000
    or (p_active_energy is not null and p_active_energy not between 0 and 50000) or p_date<current_date-7 or p_date>current_date+1
    or p_steps is null or p_date is null then raise exception 'Invalid health activity'; end if;
  if not public.user_has_pro(owner_id) then raise exception 'Pro required for background refresh'; end if;
  if not coalesce((select granted from public.consent_records where user_id=owner_id and kind='health_data' order by created_at desc limit 1),false)
    or not exists(select 1 from public.health_connections where user_id=owner_id and provider=p_source and status='connected') then
    raise exception 'Health permission required';
  end if;
  insert into public.daily_activities(user_id,date,steps,active_energy_kcal,source)
    values(owner_id,p_date,p_steps,coalesce(p_active_energy,0),p_source)
  on conflict(user_id,date) do update set steps=excluded.steps,active_energy_kcal=coalesce(p_active_energy,public.daily_activities.active_energy_kcal),source=excluded.source
    where public.daily_activities.source<>'manual';
  get diagnostics changed=row_count;
  return jsonb_build_object('synced',changed=1,'preserved_manual',changed=0);
end $$;
revoke all on function public.sync_health_activity(date,integer,numeric,text) from public,anon;
grant execute on function public.sync_health_activity(date,integer,numeric,text) to authenticated;
