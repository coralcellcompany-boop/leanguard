-- Only the server can call this. RevenueCat request_date_ms orders responses,
-- preventing delayed webhooks or concurrent refreshes from rolling state back.
create function public.reconcile_entitlement(p_user_id uuid,p_entitlement jsonb,p_verified_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result public.subscription_entitlements;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,31));
  insert into public.subscription_entitlements(user_id,entitlement_id,is_active,product_id,expires_at,
    grace_period_expires_at,status,will_renew,management_url,is_sandbox,verified_at)
  values(p_user_id,'pro',(p_entitlement->>'is_active')::boolean,p_entitlement->>'product_id',
    (p_entitlement->>'expires_at')::timestamptz,(p_entitlement->>'grace_period_expires_at')::timestamptz,
    p_entitlement->>'status',(p_entitlement->>'will_renew')::boolean,p_entitlement->>'management_url',
    (p_entitlement->>'is_sandbox')::boolean,p_verified_at)
  on conflict(user_id,entitlement_id) do update set
    is_active=excluded.is_active,product_id=excluded.product_id,expires_at=excluded.expires_at,
    grace_period_expires_at=excluded.grace_period_expires_at,status=excluded.status,will_renew=excluded.will_renew,
    management_url=excluded.management_url,is_sandbox=excluded.is_sandbox,verified_at=excluded.verified_at
  where public.subscription_entitlements.verified_at<=excluded.verified_at;
  select * into result from public.subscription_entitlements where user_id=p_user_id and entitlement_id='pro';
  return to_jsonb(result);
end $$;
revoke all on function public.reconcile_entitlement(uuid,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.reconcile_entitlement(uuid,jsonb,timestamptz) to service_role;

-- Sandbox acceptance is decided while verifying RevenueCat (server env only).
create or replace function public.user_has_pro(p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.subscription_entitlements where user_id=p_user_id and entitlement_id='pro' and is_active
  and (expires_at is null or greatest(expires_at,grace_period_expires_at)>now()));
$$;
