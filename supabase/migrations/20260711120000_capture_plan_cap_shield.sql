-- Capture the tier-enforcement shield that until now lived only in the live
-- Supabase project (created ad-hoc via MCP), so it is version-controlled and
-- reproducible. Mirrors production exactly; every statement is idempotent.
--
-- The shield: plan_limits holds per-plan caps; tenant_cap() resolves a store's
-- effective cap; enforce_plan_cap() is a BEFORE INSERT guard wired onto every
-- tier-gated table (products/categories/employees/inventory_items/branches).
-- Direct table inserts from the app cannot bypass it. Orders/day is enforced
-- separately inside create_paid_order.

create table if not exists public.plan_limits (
  plan              text primary key,
  daily_order_limit int,
  max_employees     int,
  max_products      int,
  max_categories    int,
  max_inventory     int,
  max_branches      int
);

insert into public.plan_limits
  (plan, daily_order_limit, max_employees, max_products, max_categories, max_inventory, max_branches)
values
  ('trial', 20,   2,    25,   6,    15,   1),
  ('basic', 100,  5,    100,  15,   60,   1),
  ('pro',   null, null, null, null, null, null)
on conflict (plan) do nothing;

-- Effective cap for a tenant+entity (null = unlimited). Reads the store's plan.
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
    when 'branches'   then pl.max_branches
  end
  from public.plan_limits pl
  where pl.plan = coalesce(
    (select plan from public.tenant_subscriptions where tenant_id = p_tenant), 'trial');
$$;

-- BEFORE INSERT guard: blocks a row that would exceed the tenant's cap.
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
    return new; -- unlimited (Pro)
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
    raise exception 'Your % plan allows up to % %. Upgrade to keep adding.',
      v_plan_label, v_cap, v_label;
  end if;
  return new;
end; $$;

-- Trigger function: never callable directly over the REST API (matches the
-- SECURITY DEFINER lockdown). It runs only from the cap_* triggers below.
revoke execute on function public.enforce_plan_cap() from public, anon, authenticated;

drop trigger if exists cap_products   on public.products;
drop trigger if exists cap_categories on public.categories;
drop trigger if exists cap_employees  on public.employees;
drop trigger if exists cap_inventory  on public.inventory_items;
drop trigger if exists cap_branches   on public.branches;

create trigger cap_products   before insert on public.products        for each row execute function public.enforce_plan_cap('products');
create trigger cap_categories before insert on public.categories      for each row execute function public.enforce_plan_cap('categories');
create trigger cap_employees  before insert on public.employees       for each row execute function public.enforce_plan_cap('employees');
create trigger cap_inventory  before insert on public.inventory_items for each row execute function public.enforce_plan_cap('inventory');
create trigger cap_branches   before insert on public.branches        for each row execute function public.enforce_plan_cap('branches');
