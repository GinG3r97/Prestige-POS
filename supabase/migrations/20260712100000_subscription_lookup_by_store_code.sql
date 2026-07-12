-- /subscribe identify-first gate: given a store code + the email used in the
-- POS app, return that store's subscription summary. Both must match (email
-- must be the tenant's owner or a tenant_member) — a single generic empty
-- result on any mismatch, so store codes can't be probed. Callable pre-auth.
create or replace function public.subscription_lookup(p_store_code text, p_email text)
returns table(
  tenant_id uuid,
  business_name text,
  store_code text,
  plan text,
  status text,
  current_period_end timestamptz,
  cancel_at_period_end boolean
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select t.id,
         t.business_name,
         t.store_code,
         coalesce(s.plan, 'trial'),
         coalesce(s.status, 'trialing'),
         s.current_period_end,
         coalesce(s.cancel_at_period_end, false)
  from tenants t
  left join tenant_subscriptions s on s.tenant_id = t.id
  where upper(trim(t.store_code)) = upper(trim(p_store_code))
    and (
      exists (select 1 from tenant_members m
              where m.tenant_id = t.id
                and lower(m.email) = lower(trim(p_email)))
      or exists (select 1 from auth.users u
                 where u.id = t.owner_id
                   and lower(u.email) = lower(trim(p_email)))
    );
$$;

revoke all on function public.subscription_lookup(text, text) from public;
grant execute on function public.subscription_lookup(text, text) to anon, authenticated;
