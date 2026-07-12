-- Self-serve subscribe + PayMongo checkout.
--
-- Flow: owner signs in (OTP) → picks a store → picks Basic/Pro + cycle →
-- start_subscription_checkout() records a pending upgrade_requests row →
-- the web app creates a PayMongo Checkout Session with that request id in
-- metadata → on payment, the paymongo-webhook edge function (service role)
-- calls activate_subscription_by_request() to flip the subscription to active.

alter table public.upgrade_requests
  add column if not exists provider text,
  add column if not exists provider_ref text;

-- Every store the caller owns or co-owns, with its current plan/status.
create or replace function public.my_stores()
  returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id', t.id,
    'business_name', t.business_name,
    'store_code', t.store_code,
    'plan', coalesce(s.plan, 'trial'),
    'status', coalesce(s.status, 'trialing'),
    'current_period_end', s.current_period_end
  ) order by t.created_at), '[]'::jsonb)
  from public.tenants t
  left join public.tenant_subscriptions s on s.tenant_id = t.id
  where t.owner_id = auth.uid() or public.is_tenant_member(t.id);
$function$;
grant execute on function public.my_stores() to authenticated;

-- Create a pending PayMongo request for a store the caller controls.
create or replace function public.start_subscription_checkout(p_tenant uuid, p_plan text, p_cycle text)
  returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_amount int; v_name text; v_code text; v_id uuid;
begin
  if not (exists(select 1 from public.tenants where id=p_tenant and owner_id=auth.uid())
          or public.is_tenant_member(p_tenant)) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_plan not in ('basic','pro') then raise exception 'BAD_PLAN'; end if;
  if p_cycle not in ('monthly','yearly') then raise exception 'BAD_CYCLE'; end if;
  v_amount := case
    when p_plan='basic' and p_cycle='monthly' then 49900
    when p_plan='basic' and p_cycle='yearly'  then 499000
    when p_plan='pro'   and p_cycle='monthly' then 149900
    when p_plan='pro'   and p_cycle='yearly'  then 1499000
  end;
  select business_name, store_code into v_name, v_code from public.tenants where id=p_tenant;
  insert into public.upgrade_requests(tenant_id, store_code, business_name, email,
      requested_plan, billing_cycle, amount_cents, status, provider)
  values (p_tenant, v_code, v_name, coalesce(auth.jwt()->>'email',''),
      p_plan, p_cycle, v_amount, 'pending', 'paymongo')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'amount_cents', v_amount,
      'business_name', v_name, 'plan', p_plan, 'cycle', p_cycle);
end; $function$;
grant execute on function public.start_subscription_checkout(uuid, text, text) to authenticated;

-- Called by the PayMongo webhook (service role) once payment succeeds.
create or replace function public.activate_subscription_by_request(p_id uuid, p_ref text default null)
  returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare r public.upgrade_requests; v_end timestamptz; v_price int;
begin
  select * into r from public.upgrade_requests where id = p_id;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status = 'verified' then return jsonb_build_object('ok', true, 'already', true); end if;
  v_end := now() + (case when r.billing_cycle='yearly' then interval '1 year' else interval '1 month' end);
  v_price := case when r.billing_cycle='yearly' then round(r.amount_cents/12.0)::int else r.amount_cents end;
  update public.upgrade_requests
     set status='verified', verified_at=now(), verified_by='paymongo',
         provider_ref=coalesce(p_ref, provider_ref)
   where id=r.id;
  update public.tenant_subscriptions
     set plan=r.requested_plan, status='active', price_cents=v_price,
         billing_cycle=r.billing_cycle, current_period_end=v_end, updated_at=now()
   where tenant_id=r.tenant_id;
  if not found then
    insert into public.tenant_subscriptions(tenant_id, plan, status, price_cents,
        billing_cycle, started_at, current_period_end)
    values (r.tenant_id, r.requested_plan, 'active', v_price, r.billing_cycle, now(), v_end);
  end if;
  return jsonb_build_object('ok', true, 'tenant', r.tenant_id, 'plan', r.requested_plan);
end; $function$;
revoke all on function public.activate_subscription_by_request(uuid, text) from public, anon, authenticated;
grant execute on function public.activate_subscription_by_request(uuid, text) to service_role;
