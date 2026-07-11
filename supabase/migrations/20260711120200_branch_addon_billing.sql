-- Additional-branch purchases reuse the existing upgrade_requests + PayMongo
-- pipeline. A branch add-on is an upgrade_requests row with kind='branch_addon'
-- and branch_qty; activation increments tenant_subscriptions.extra_branches
-- instead of changing the plan. The PayMongo webhook is unchanged (it already
-- calls activate_subscription_by_request with the request id).

alter table public.upgrade_requests
  add column if not exists kind text not null default 'plan'
    check (kind in ('plan','branch_addon')),
  add column if not exists branch_qty int
    check (branch_qty is null or branch_qty > 0);

-- Start a checkout for N additional branches (Pro only). Price is server-side.
-- NOTE: placeholder pricing PHP 499/mo or 4,990/yr per branch -- confirm before launch.
create or replace function public.start_branch_addon_checkout(
  p_tenant uuid, p_qty int, p_cycle text)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_amount int; v_name text; v_code text; v_id uuid;
        v_plan text; v_status text; v_per int;
begin
  if not (exists(select 1 from public.tenants where id=p_tenant and owner_id=auth.uid())
          or public.is_tenant_member(p_tenant)) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'BAD_QTY'; end if;
  if p_cycle not in ('monthly','yearly') then raise exception 'BAD_CYCLE'; end if;

  -- Only an active Pro store may buy extra branches.
  select plan, status into v_plan, v_status
    from public.tenant_subscriptions where tenant_id=p_tenant;
  if coalesce(v_plan,'trial') <> 'pro' or coalesce(v_status,'') <> 'active' then
    raise exception 'PRO_REQUIRED';
  end if;

  v_per := case when p_cycle='yearly' then 499000 else 49900 end;
  v_amount := v_per * p_qty;
  select business_name, store_code into v_name, v_code from public.tenants where id=p_tenant;

  insert into public.upgrade_requests(tenant_id, store_code, business_name, email,
      kind, branch_qty, billing_cycle, amount_cents, status, provider)
  values (p_tenant, v_code, v_name, coalesce(auth.jwt()->>'email',''),
      'branch_addon', p_qty, p_cycle, v_amount, 'pending', 'paymongo')
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'amount_cents', v_amount, 'qty', p_qty,
      'business_name', v_name, 'cycle', p_cycle, 'kind', 'branch_addon');
end; $$;

revoke execute on function public.start_branch_addon_checkout(uuid,int,text) from public, anon;
grant  execute on function public.start_branch_addon_checkout(uuid,int,text) to authenticated;

-- Activation now branches on kind. Plan upgrades behave exactly as before.
create or replace function public.activate_subscription_by_request(p_id uuid, p_ref text default null::text)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare r public.upgrade_requests; v_end timestamptz; v_price int;
begin
  select * into r from public.upgrade_requests where id = p_id;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status = 'verified' then return jsonb_build_object('ok', true, 'already', true); end if;

  if r.kind = 'branch_addon' then
    update public.upgrade_requests
       set status='verified', verified_at=now(), verified_by='paymongo',
           provider_ref=coalesce(p_ref, provider_ref)
     where id=r.id;
    update public.tenant_subscriptions
       set extra_branches = coalesce(extra_branches,0) + coalesce(r.branch_qty,0),
           updated_at=now()
     where tenant_id=r.tenant_id;
    return jsonb_build_object('ok', true, 'tenant', r.tenant_id,
        'kind','branch_addon', 'added', r.branch_qty);
  end if;

  -- Plan upgrade (unchanged from the original).
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
end; $$;

-- Keep activation service-role only (matches the RPC lockdown).
revoke execute on function public.activate_subscription_by_request(uuid, text) from public, anon, authenticated;
grant  execute on function public.activate_subscription_by_request(uuid, text) to service_role;
