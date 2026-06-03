-- The `tenants_after_insert_create_features` function is a trigger function
-- and shouldn't be callable directly via the REST API. Revoke EXECUTE from
-- public-facing roles — the trigger continues to fire because it runs as
-- the trigger owner (postgres), independent of caller permissions.

revoke execute on function public.tenants_after_insert_create_features() from public;
revoke execute on function public.tenants_after_insert_create_features() from anon;
revoke execute on function public.tenants_after_insert_create_features() from authenticated;
