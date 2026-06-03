-- Adds an explicit Material-icon name to categories and modifier groups so
-- owner-created entries can pick a theme-matching icon at create time instead
-- of relying on emoji or keyword auto-mapping.
--
-- The value is a string matching one of the curated icons in the Flutter
-- picker (e.g. 'coffee_outlined'). The picker is the source of truth for
-- which names are valid — we don't enforce it in SQL to keep the picker
-- free to evolve without further migrations.

alter table public.categories
  add column if not exists icon_name text;

alter table public.modifier_groups
  add column if not exists icon_name text;
