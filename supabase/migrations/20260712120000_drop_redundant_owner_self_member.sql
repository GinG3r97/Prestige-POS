-- Remove the redundant "owner is also a co-owner of their own store" rows.
--
-- Background: an earlier change backfilled every owner's email into
-- tenant_members and added a trigger to keep doing so on new stores, to make
-- owners pass a login gate. But both login gates match the primary owner via
-- their real auth.users.email (mobile_login_check: ou.email; web: the auth
-- user already exists), so the self-row is never needed. It only caused the
-- owner to appear twice in the Co-owners list (once as Owner, once as a
-- removable co-owner). my_tenant_id()/is_tenant_member() also resolve owners
-- via owner_id first, so nothing depends on the self-row.

drop trigger if exists tenants_add_owner_member on public.tenants;
drop function if exists public.tenants_after_insert_add_owner_member();

delete from public.tenant_members m
using public.tenants t, auth.users u
where m.tenant_id = t.id
  and u.id = t.owner_id
  and lower(m.email) = lower(u.email);
