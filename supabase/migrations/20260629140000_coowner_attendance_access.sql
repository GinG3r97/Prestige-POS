-- Let co-owners (public.tenant_members) use the web attendance-setup page,
-- not just the original owner. Two changes:
--   1. tenants SELECT RLS — allow a member to read their store's row (the
--      page reads geofence/store_code directly). Writes stay owner-only;
--      the geofence write goes through the SECURITY DEFINER RPC below.
--   2. set_store_geofence — resolve the store via my_tenant_id() (which now
--      honours membership) instead of owner_id, so co-owners can save it.

drop policy if exists "owner reads own tenants" on public.tenants;
create policy "owner reads own tenants" on public.tenants
  for select
  using ((select auth.uid()) = owner_id or public.is_tenant_member(id));

create or replace function public.set_store_geofence(
  p_lat double precision,
  p_lng double precision,
  p_radius integer default 200
) returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
as $function$
declare v_tid uuid;
begin
  v_tid := public.my_tenant_id();
  if v_tid is null then raise exception 'NOT_OWNER'; end if;
  update public.tenants
     set geo_lat = p_lat, geo_lng = p_lng, geo_radius_m = coalesce(p_radius, 200)
   where id = v_tid;
  return jsonb_build_object('ok', true);
end; $function$;
