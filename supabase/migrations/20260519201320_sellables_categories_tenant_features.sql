-- Sellables architecture: tenant-owned categories, polymorphic sellables,
-- and per-tenant feature flags that gate which nav tabs appear.
--
-- Every "sellable thing" (coffee, pastry, book, day pass, hot-desk hour,
-- monthly membership, meeting room slot) lives in `public.sellables`.
-- The `kind` column hints at UI behavior:
--   'sell'      — instant ring-up (coffee, food, books, soda)
--   'reserve'   — calendar slot reservation (meeting rooms)
--   'timer'     — start/stop a clock (hot-desk hour)
--   'subscribe' — recurring membership
--   'service'   — drop-off ticket (laundry, repair)
-- Stateful concerns (bookings, sessions, memberships) live in their own
-- tables in later migrations and reference sellables.id.

-- ── categories ─────────────────────────────────────────────────────────
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  emoji text not null default '',
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index categories_tenant_idx on public.categories(tenant_id, sort_order);

-- ── sellables ──────────────────────────────────────────────────────────
create table public.sellables (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null,
  subtitle text not null default '',
  emoji text not null default '',
  kind text not null default 'sell'
    check (kind in ('sell','reserve','timer','subscribe','service')),
  -- Money stored as integer centavos to avoid floating-point errors.
  base_price_cents int not null default 0 check (base_price_cents >= 0),
  -- Countable inventory items (books, bottled drinks). Recipe-built items
  -- like coffee will have tracks_own_stock=false and use the inventory
  -- recipe system (later turn).
  tracks_own_stock boolean not null default false,
  own_stock int not null default 0 check (own_stock >= 0),
  low_stock_threshold int not null default 0 check (low_stock_threshold >= 0),
  available boolean not null default true,
  tag text check (tag in ('hit','new','sale') or tag is null),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sellables_tenant_idx on public.sellables(tenant_id);
create index sellables_category_idx on public.sellables(category_id);
create index sellables_kind_idx on public.sellables(tenant_id, kind);

-- ── tenant_features ────────────────────────────────────────────────────
-- Explicit feature flags drive which nav tabs the tenant sees. Set during
-- onboarding via the "What do you sell?" chip selection, editable later in
-- Settings. `sell` is implicit (everyone has it) so it's not a flag here.
create table public.tenant_features (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  reserve_enabled boolean not null default false,
  timer_enabled boolean not null default false,
  subscribe_enabled boolean not null default false,
  service_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

-- ── Auto-create tenant_features row when a tenant is inserted ──────────
-- Keeps the 1:1 relationship in sync without app-side INSERTs.
create or replace function public.tenants_after_insert_create_features()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.tenant_features (tenant_id)
  values (new.id)
  on conflict (tenant_id) do nothing;
  return new;
end;
$$;

drop trigger if exists tenants_features_trigger on public.tenants;
create trigger tenants_features_trigger
  after insert on public.tenants
  for each row execute function public.tenants_after_insert_create_features();

-- Back-fill features rows for tenants that already exist (the test tenant
-- created before this migration).
insert into public.tenant_features (tenant_id)
select id from public.tenants
on conflict (tenant_id) do nothing;

-- ── RLS ────────────────────────────────────────────────────────────────
alter table public.categories enable row level security;
alter table public.sellables enable row level security;
alter table public.tenant_features enable row level security;

create policy "owner reads own categories"
  on public.categories for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own categories"
  on public.categories for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own sellables"
  on public.sellables for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own sellables"
  on public.sellables for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own features"
  on public.tenant_features for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own features"
  on public.tenant_features for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));
