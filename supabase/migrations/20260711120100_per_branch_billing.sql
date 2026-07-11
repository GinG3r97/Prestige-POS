-- Per-branch billing. Pro includes 1 branch; each additional branch is a paid
-- add-on tracked in tenant_subscriptions.extra_branches (sold on the web, so it
-- stays App Store / Play compliant). Only Pro can open branches beyond the
-- first -- Free/Basic keep their single store. No existing store has >1 branch,
-- so this is non-destructive.

alter table public.tenant_subscriptions
  add column if not exists extra_branches int not null default 0
    check (extra_branches >= 0);

-- Pro's base branch allowance is now 1 (was unlimited); extras are per-tenant.
update public.plan_limits set max_branches = 1 where plan = 'pro';

-- Branch cap becomes plan-aware: Pro = 1 + paid extra_branches; everyone else
-- uses their flat plan_limits.max_branches. All other entities unchanged.
create or replace function public.tenant_cap(p_tenant uuid, p_entity text)
returns integer
language sql stable security definer set search_path to 'public'
as $$
  select case p_entity
    when 'orders'     then pl.daily_order_limit
    when 'employees'  then pl.max_employees
    when 'products'   then pl.max_products
    when 'categories' then pl.max_categories
    when 'inventory'  then pl.max_inventory
    when 'branches'   then
      case when coalesce(sub.plan, 'trial') = 'pro'
           then coalesce(pl.max_branches, 1) + coalesce(sub.extra_branches, 0)
           else pl.max_branches end
  end
  from public.plan_limits pl
  left join public.tenant_subscriptions sub on sub.tenant_id = p_tenant
  where pl.plan = coalesce(sub.plan, 'trial');
$$;

-- Softer, App Store / Play-safe wording on the cap block (no purchase verb).
create or replace function public.enforce_plan_cap()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_entity text := TG_ARGV[0];
  v_cap int; v_count int; v_plan text; v_label text; v_plan_label text;
begin
  v_cap := public.tenant_cap(new.tenant_id, v_entity);
  if v_cap is null then
    return new;
  end if;
  execute format('select count(*) from public.%I where tenant_id = $1', TG_TABLE_NAME)
    into v_count using new.tenant_id;
  if v_count >= v_cap then
    select coalesce(plan,'trial') into v_plan
      from public.tenant_subscriptions where tenant_id = new.tenant_id;
    v_plan := coalesce(v_plan,'trial');
    v_label := case v_entity
      when 'employees' then 'staff' when 'products' then 'products'
      when 'categories' then 'categories' when 'inventory' then 'inventory items'
      when 'branches' then 'branches' else v_entity end;
    v_plan_label := case v_plan
      when 'trial' then 'Free' when 'basic' then 'Basic'
      when 'pro' then 'Pro' else initcap(v_plan) end;
    raise exception 'Your % plan allows up to % %. See other plans to add more.',
      v_plan_label, v_cap, v_label;
  end if;
  return new;
end; $$;

-- Replacing the function preserves grants, but keep the trigger function
-- un-callable over the REST API regardless (defense-in-depth).
revoke execute on function public.enforce_plan_cap() from public, anon, authenticated;
