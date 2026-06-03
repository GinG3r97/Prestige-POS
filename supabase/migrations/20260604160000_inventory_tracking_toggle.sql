-- Per-product inventory tracking + a store-wide master switch.
-- Effective tracking = tenant.inventory_tracking_enabled AND product.track_inventory
--                      AND product_type.deducts_stock.
-- When tracking is off, a product sells freely: no recipe deduction, no
-- out-of-stock blocking.
alter table public.products
  add column if not exists track_inventory boolean not null default true;

alter table public.tenants
  add column if not exists inventory_tracking_enabled boolean not null default true;

-- Ginger Store isn't using inventory yet (new drinks at 0 stock), so turn the
-- master switch OFF — everything sells freely until the owner flips it on.
update public.tenants
  set inventory_tracking_enabled = false
  where id = '7b49e801-d5fc-4914-be3f-c8d458be34a8';
