-- Optional free-form display override for the unit symbol. The canonical
-- `unit` column still drives recipe math (mass / volume / count family,
-- g↔kg conversion). When set, the inventory UI shows this string instead
-- of the preset symbol — useful for "shot", "slice", "tray" etc.
alter table public.inventory_items
  add column if not exists unit_label text;
