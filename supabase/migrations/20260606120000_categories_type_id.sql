-- Link each category (now reframed as a "sub-type") to a product type, so the
-- Sell page can browse Product Type -> Sub-type -> Product. Purely additive:
-- the column is nullable, and SET NULL means deleting a type leaves its
-- sub-types intact (they fall into the app's "Other" bucket). The currently
-- shipped app doesn't select this column, so adding it is a no-op for it.
alter table public.categories
  add column if not exists type_id uuid
    references public.product_types(id) on delete set null;

create index if not exists categories_type_idx on public.categories(type_id);

-- Best-effort, NON-DESTRUCTIVE backfill so existing stores get a sensible
-- starting grouping. Touches ONLY categories whose type_id is still null;
-- never modifies products and never clears an existing link. Owners can
-- re-assign any sub-type's type in Maintenance afterwards.
do $$
declare
  v_tenant   uuid;
  v_drink_id uuid;
  v_food_id  uuid;
begin
  for v_tenant in (select id from public.tenants) loop
    -- The tenant's Drink-ish type (onboarding + legacy both name it 'Drink').
    select id into v_drink_id from public.product_types
      where tenant_id = v_tenant and lower(name) = 'drink'
      order by sort_order limit 1;

    -- Default non-drink bucket: 'Item' (new onboarding) or 'Food' (legacy
    -- SQL-seeded tenants) — whichever exists, lowest sort_order first.
    select id into v_food_id from public.product_types
      where tenant_id = v_tenant and lower(name) in ('item', 'food')
      order by sort_order limit 1;

    -- Drink keywords -> Drink type.
    if v_drink_id is not null then
      update public.categories c
        set type_id = v_drink_id
        where c.tenant_id = v_tenant
          and c.type_id is null
          and lower(c.name) ~ '(coffee|tea|espresso|latte|frappe|smoothie|shake|juice|soda|milk\s*tea|refresher|matcha|drink)';
    end if;

    -- Everything still unlinked -> the default non-drink bucket. If the tenant
    -- has neither Item nor Food, rows stay null and surface under "Other".
    if v_food_id is not null then
      update public.categories c
        set type_id = v_food_id
        where c.tenant_id = v_tenant
          and c.type_id is null;
    end if;
  end loop;
end $$;
