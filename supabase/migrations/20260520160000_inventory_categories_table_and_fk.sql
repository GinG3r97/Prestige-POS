-- ─── 1. inventory_categories table ───────────────────────────────────
-- Per-tenant catalog of inventory categories (Fresh Vegetables, Books,
-- Placeholder, Coffee & Tea, etc.). Owners manage these in
-- Maintenance → Inventory categories. Replaces the free-text `category`
-- column on inventory_items, which becomes the denormalized display
-- name kept in sync via the writer + the foreign key.
create table if not exists public.inventory_categories (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  name        text not null,
  icon_name   text,
  sort_order  integer not null default 0,
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index if not exists inventory_categories_tenant_idx
  on public.inventory_categories (tenant_id, sort_order);

alter table public.inventory_categories enable row level security;
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname='public' and tablename='inventory_categories'
               and policyname='inventory_categories_owner_all') then
    drop policy inventory_categories_owner_all on public.inventory_categories;
  end if;
end $$;
create policy inventory_categories_owner_all
  on public.inventory_categories for all
  using (tenant_id in (select id from public.tenants where owner_id = auth.uid()))
  with check (tenant_id in (select id from public.tenants where owner_id = auth.uid()));

create or replace function public.touch_inventory_categories_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_inv_cats on public.inventory_categories;
create trigger trg_touch_inv_cats
before update on public.inventory_categories
for each row execute function public.touch_inventory_categories_updated_at();

-- Backfill from existing inventory_items.category values, one row per
-- (tenant, distinct category). Best-effort icon guess based on name.
insert into public.inventory_categories (tenant_id, name, sort_order, is_system, icon_name)
select tenant_id,
       category,
       (row_number() over (partition by tenant_id order by category)) * 10 as sort_order,
       true as is_system,
       case lower(category)
         when 'books' then 'menu_book_outlined'
         when 'coffee & tea' then 'coffee_outlined'
         when 'dairy' then 'water_drop_outlined'
         when 'syrups & sauces' then 'local_drink_outlined'
         when 'bakery' then 'bakery_dining_outlined'
         when 'food ingredients' then 'restaurant_outlined'
         when 'packaging' then 'shopping_bag_outlined'
         when 'cleaning' then 'tune_outlined'
         when 'fresh vegetables' then 'restaurant_outlined'
         when 'meat & poultry' then 'set_meal_outlined'
         when 'dry, wet & canned' then 'shopping_bag_outlined'
         when 'placeholder' then 'label_outlined'
         else null
       end as icon_name
from (
  select distinct tenant_id, category
  from public.inventory_items
  where category is not null and category <> ''
) src
on conflict (tenant_id, name) do nothing;

-- FK column on inventory_items.
alter table public.inventory_items
  add column if not exists inventory_category_id uuid
    references public.inventory_categories(id) on delete set null;

create index if not exists inventory_items_inv_category_idx
  on public.inventory_items (inventory_category_id);

update public.inventory_items i
set inventory_category_id = c.id
from public.inventory_categories c
where i.tenant_id = c.tenant_id
  and lower(i.category) = lower(c.name)
  and i.inventory_category_id is null;
