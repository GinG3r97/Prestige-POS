-- Master modifier groups (Size, Temperature, Strength, plus any owner-defined
-- groups like Milk Type or Sweetness) and their options.
--
-- Products opt-in to specific groups, but the group itself is tenant-owned
-- and shared across the menu. Renaming a group here flows through to every
-- product that uses it.

create table public.modifier_groups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  emoji text not null default '',
  required boolean not null default false,
  -- Index of the default option in the (sort_order-ordered) options list.
  default_index int not null default 0 check (default_index >= 0),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index modifier_groups_tenant_idx
  on public.modifier_groups(tenant_id, sort_order);

create table public.modifier_options (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.modifier_groups(id) on delete cascade,
  name text not null,
  -- Master-level default price delta in centavos. Products may override
  -- per-product (in the per-product modifier table that comes in turn 1b).
  price_delta_cents int not null default 0,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (group_id, name)
);

create index modifier_options_group_idx
  on public.modifier_options(group_id, sort_order);

-- ── RLS ───────────────────────────────────────────────────────────────
alter table public.modifier_groups enable row level security;
alter table public.modifier_options enable row level security;

create policy "owner reads own modifier groups"
  on public.modifier_groups for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own modifier groups"
  on public.modifier_groups for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own modifier options"
  on public.modifier_options for select
  using (exists (
    select 1 from public.modifier_groups g
    join public.tenants t on t.id = g.tenant_id
    where g.id = group_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own modifier options"
  on public.modifier_options for all
  using (exists (
    select 1 from public.modifier_groups g
    join public.tenants t on t.id = g.tenant_id
    where g.id = group_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.modifier_groups g
    join public.tenants t on t.id = g.tenant_id
    where g.id = group_id and t.owner_id = auth.uid()
  ));

-- ── Back-fill defaults for any existing tenants ───────────────────────
-- New tenants get these via completeOnboarding (Flutter side). This block
-- covers tenants that already exist before the migration was applied so
-- they don't end up with an empty Modifier Groups screen.
do $$
declare
  v_tenant uuid;
  v_size_id uuid;
  v_temp_id uuid;
  v_strength_id uuid;
begin
  for v_tenant in (
    select id from public.tenants
    where id not in (select tenant_id from public.modifier_groups)
  ) loop
    insert into public.modifier_groups
      (tenant_id, name, emoji, required, default_index, sort_order)
    values (v_tenant, 'Size', '📏', true, 1, 10)
    returning id into v_size_id;
    insert into public.modifier_options (group_id, name, sort_order) values
      (v_size_id, 'Small', 0),
      (v_size_id, 'Medium', 1),
      (v_size_id, 'Large', 2);

    insert into public.modifier_groups
      (tenant_id, name, emoji, required, default_index, sort_order)
    values (v_tenant, 'Temperature', '🌡', true, 0, 20)
    returning id into v_temp_id;
    insert into public.modifier_options (group_id, name, sort_order) values
      (v_temp_id, 'Hot', 0),
      (v_temp_id, 'Cold', 1);

    insert into public.modifier_groups
      (tenant_id, name, emoji, required, default_index, sort_order)
    values (v_tenant, 'Strength', '⚡', false, 0, 30)
    returning id into v_strength_id;
    insert into public.modifier_options (group_id, name, sort_order) values
      (v_strength_id, 'Mild', 0),
      (v_strength_id, 'Strong', 1);
  end loop;
end $$;
