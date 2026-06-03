-- Per-tenant add-ons (extra shot, oat milk, syrup pumps, etc.). Cashiers
-- attach these at order time from any product whose category matches the
-- add-on's allow-list.
--
-- Shape choices:
--   • recipe stays jsonb (array of {inventory_item_id, quantity}) — same
--     pattern products use.
--   • applicable_category_ids is uuid[] referencing categories.id. Empty
--     array means "applies to every category" (the cashier sees it on
--     every product). We don't FK-constrain the array contents — a
--     deleted category just drops out of the picker.

create table public.add_ons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  emoji text not null default '✨',
  icon_name text,
  price_delta_cents int not null default 0 check (price_delta_cents >= 0),
  -- 0 = unlimited quantity per line.
  max_quantity int not null default 0 check (max_quantity >= 0),
  applicable_category_ids uuid[] not null default '{}'::uuid[],
  recipe jsonb not null default '[]'::jsonb,
  is_system boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index add_ons_tenant_idx
  on public.add_ons(tenant_id, sort_order);

alter table public.add_ons enable row level security;

create policy "owner reads own add-ons"
  on public.add_ons for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own add-ons"
  on public.add_ons for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
