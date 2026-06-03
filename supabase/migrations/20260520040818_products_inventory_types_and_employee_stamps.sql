-- Products, inventory, and product types — the heart of the POS goes live.
--
-- ── What ships here ──────────────────────────────────────────────────
-- 1. `product_types`     — tenant-owned behavior buckets (Drink, Food,
--                          Pastry, Book, Retail, Service). Each type
--                          flags whether it supports modifiers and
--                          whether it deducts from stock on a sale.
-- 2. `inventory_items`   — tenant-owned stock rows (beans, milk, cups,
--                          books). All in the item's own unit (g, ml,
--                          pcs). Recipes deduct from here on sale.
-- 3. `products`          — tenant-owned sellables. Each row references a
--                          `product_type`, optionally a `category`, and
--                          carries its recipe + modifier-group opt-ins
--                          + per-option recipe adjustments as jsonb (the
--                          existing in-memory shape ports 1-to-1).
-- 4. `orders` patch      — adds `employee_id` (FK, nullable so a sale
--                          made before any employee row exists doesn't
--                          break) and `employee_name` (snapshot for
--                          receipt durability after the employee row is
--                          edited or removed).
--
-- ── Why jsonb for recipes / modifier links ───────────────────────────
-- The existing Dart side already uses object lists for these (RecipeLine,
-- ModifierAdjustment, modifierGroups). Storing them as jsonb keeps the
-- shape, lets us hydrate via PostgREST without joins, and matches the
-- pattern we already use on employees.schedule and employment_templates
-- .leave_type_ids. We can promote to dedicated tables later if we need
-- to query across products by ingredient.

-- ── 1.  product_types ────────────────────────────────────────────────
create table public.product_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  icon_name text,
  -- True for types whose products can attach modifier groups (Size,
  -- Temperature, etc.). Drinks yes; books / services no.
  supports_modifiers boolean not null default false,
  -- True for types whose products consume from inventory on sale via the
  -- product's recipe. Services / non-stock SKUs set this false.
  deducts_stock boolean not null default true,
  -- Seeded types (Drink/Food/Pastry/Book/Retail/Service) are flagged so
  -- the UI can hide the delete button; owners can still rename / re-icon
  -- them or change the flags.
  is_system boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index product_types_tenant_idx
  on public.product_types(tenant_id, sort_order);

-- ── 2.  inventory_items ──────────────────────────────────────────────
create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  sku text not null default '',
  category text not null default 'General',
  -- Unit stored as text matching StockUnit dbValue: 'g','kg','ml','L',
  -- 'pcs','pack'. We don't enforce a CHECK constraint here — the Dart
  -- enum is the source of truth and may grow over time.
  unit text not null default 'pcs',
  current_stock numeric(14,3) not null default 0,
  low_stock_threshold numeric(14,3) not null default 0,
  cost_per_unit_cents int not null default 0 check (cost_per_unit_cents >= 0),
  supplier text not null default '',
  last_restocked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index inventory_items_tenant_idx
  on public.inventory_items(tenant_id, category);

-- ── 3.  products ─────────────────────────────────────────────────────
create table public.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  -- Behavior bucket; SET NULL so deleting a type doesn't nuke the
  -- product (UI surfaces an "untyped" badge until the owner fixes it).
  type_id uuid references public.product_types(id) on delete set null,
  -- Menu group. Same SET NULL policy as type_id.
  category_id uuid references public.categories(id) on delete set null,

  name text not null,
  subtitle text not null default '',
  base_price_cents int not null default 0 check (base_price_cents >= 0),
  emoji text not null default '',
  icon_name text,
  -- 'hit' | 'new' | 'sale' | null — small badge on the product card.
  tag text,

  available boolean not null default true,
  sort_order int not null default 0,

  -- Modifier-group opt-ins. Array of modifier_groups.id; preserves
  -- ordering the owner picked in the product form.
  modifier_group_ids uuid[] not null default '{}'::uuid[],

  -- Base recipe: array of {inventory_item_id, quantity}.
  recipe jsonb not null default '[]'::jsonb,

  -- Per-modifier-option adjustments — multipliers or extra recipe lines
  -- keyed by modifier_options.id. Array of
  --   {group_id, option_id, kind: 'multiplier'|'addLines', multiplier, add_lines: [...]}
  modifier_adjustments jsonb not null default '[]'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index products_tenant_idx
  on public.products(tenant_id, sort_order);
create index products_type_idx on public.products(type_id);
create index products_category_idx on public.products(category_id);

-- ── 4.  Order stamps ────────────────────────────────────────────────
alter table public.orders
  add column if not exists employee_id uuid
    references public.employees(id) on delete set null,
  add column if not exists employee_name text;

create index if not exists orders_employee_idx
  on public.orders(employee_id);

-- ── RLS — owner-only across the three new tables ────────────────────
alter table public.product_types enable row level security;
alter table public.inventory_items enable row level security;
alter table public.products enable row level security;

create policy "owner reads own product types"
  on public.product_types for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own product types"
  on public.product_types for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner reads own inventory"
  on public.inventory_items for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own inventory"
  on public.inventory_items for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner reads own products"
  on public.products for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own products"
  on public.products for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

-- ── Back-fill default product types for existing tenants ────────────
-- New tenants get these via completeOnboarding (Flutter side). This
-- block covers tenants that already exist before the migration ran.
do $$
declare
  v_tenant uuid;
begin
  for v_tenant in (
    select id from public.tenants
    where id not in (select tenant_id from public.product_types)
  ) loop
    insert into public.product_types
      (tenant_id, name, icon_name, supports_modifiers, deducts_stock, is_system, sort_order)
    values
      (v_tenant, 'Drink', 'local_cafe_outlined', true, true, true, 10),
      (v_tenant, 'Food', 'restaurant_outlined', false, true, true, 20),
      (v_tenant, 'Pastry', 'bakery_dining_outlined', false, true, true, 30),
      (v_tenant, 'Book', 'menu_book_outlined', false, true, true, 40),
      (v_tenant, 'Retail', 'shopping_bag_outlined', false, true, true, 50),
      (v_tenant, 'Service', 'handshake_outlined', false, false, true, 60);
  end loop;
end $$;
