-- Pin search_path on SECURITY-relevant trigger functions (advisor 0011).
alter function public.touch_updated_at() set search_path = public, pg_temp;
alter function public.touch_inventory_categories_updated_at() set search_path = public, pg_temp;
alter function public.touch_printer_configs_updated_at() set search_path = public, pg_temp;
alter function public.touch_bookable_resources_updated_at() set search_path = public, pg_temp;
alter function public.touch_bookings_updated_at() set search_path = public, pg_temp;

-- Remove the broad anon SELECT (list) policy on the public product-images
-- bucket (advisor 0025). Public-URL display still works via the CDN.
drop policy if exists product_images_public_read on storage.objects;
