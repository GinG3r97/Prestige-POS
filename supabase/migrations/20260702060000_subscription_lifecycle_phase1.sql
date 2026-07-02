-- Subscription lifecycle, phase 1 (period-based, manual renewal).
--
-- Rules (abuse-proof): access always equals what was paid for. Upgrades are
-- paid immediately (start_subscription_checkout). Cancel/downgrade take effect
-- at period end via cancel_at_period_end. A paid plan that reaches its period
-- end with no renewal drops to Trial immediately (no auto-charge on GCash).
--
-- Schedule (run once, outside this migration):
--   select cron.schedule('expire-subscriptions','*/15 * * * *',
--     $$ select public.expire_due_subscriptions(); $$);

alter table public.tenant_subscriptions
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists scheduled_plan text,
  add column if not exists auto_renew boolean not null default false;

create or replace function public.expire_due_subscriptions()
  returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare n int;
begin
  update public.tenant_subscriptions
     set plan='trial', status='trialing', price_cents=0,
         billing_cycle='monthly', current_period_end=null,
         cancel_at_period_end=false, scheduled_plan=null, updated_at=now()
   where plan <> 'trial'
     and current_period_end is not null
     and current_period_end < now();
  get diagnostics n = row_count;
  return n;
end; $function$;
revoke all on function public.expire_due_subscriptions() from public, anon, authenticated;
grant execute on function public.expire_due_subscriptions() to service_role;

create or replace function public.set_subscription_cancel(p_tenant uuid, p_cancel boolean)
  returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not (exists(select 1 from public.tenants where id=p_tenant and owner_id=auth.uid())
          or public.is_tenant_member(p_tenant)) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.tenant_subscriptions
     set cancel_at_period_end = p_cancel,
         scheduled_plan = case when p_cancel then 'trial' else null end,
         updated_at = now()
   where tenant_id = p_tenant;
  return jsonb_build_object('ok', true, 'cancel_at_period_end', p_cancel);
end; $function$;
grant execute on function public.set_subscription_cancel(uuid, boolean) to authenticated;
