-- 1. image_url on products + add_ons. Public URL of an image uploaded to
--    Supabase Storage (the `product-images` bucket). Null = no image →
--    client falls back to icon, then emoji.
alter table public.products    add column if not exists image_url text;
alter table public.add_ons     add column if not exists image_url text;

-- 2. Create the `product-images` bucket. Public so URLs render in <img>
--    without signed-URL plumbing; writes are still RLS-gated below.
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = excluded.public;

-- 3. Object-level policies. Object path is `<tenant_id>/<file>.jpg`, so we
--    derive the tenant from the first path segment and require the caller
--    to own that tenant via `public.tenant_id`.
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname = 'storage' and tablename = 'objects'
               and policyname = 'product_images_owner_insert') then
    drop policy product_images_owner_insert on storage.objects;
  end if;
  if exists (select 1 from pg_policies
             where schemaname = 'storage' and tablename = 'objects'
               and policyname = 'product_images_owner_update') then
    drop policy product_images_owner_update on storage.objects;
  end if;
  if exists (select 1 from pg_policies
             where schemaname = 'storage' and tablename = 'objects'
               and policyname = 'product_images_owner_delete') then
    drop policy product_images_owner_delete on storage.objects;
  end if;
  if exists (select 1 from pg_policies
             where schemaname = 'storage' and tablename = 'objects'
               and policyname = 'product_images_public_read') then
    drop policy product_images_public_read on storage.objects;
  end if;
end $$;

create policy product_images_public_read
  on storage.objects for select
  using (bucket_id = 'product-images');

create policy product_images_owner_insert
  on storage.objects for insert
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] in (
      select t.id::text from public.tenants t where t.owner_id = auth.uid()
    )
  );

create policy product_images_owner_update
  on storage.objects for update
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] in (
      select t.id::text from public.tenants t where t.owner_id = auth.uid()
    )
  );

create policy product_images_owner_delete
  on storage.objects for delete
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] in (
      select t.id::text from public.tenants t where t.owner_id = auth.uid()
    )
  );
