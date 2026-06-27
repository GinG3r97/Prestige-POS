-- Self-service account deletion (Apple Guideline 5.1.1(v) — apps that create
-- accounts must let users delete them in-app). Deletes the caller's stores
-- (cascades all tenant data) then the auth user itself. SECURITY DEFINER so it
-- can remove the auth.users row; scoped strictly to auth.uid() so a user can
-- only ever delete their own account.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  -- Remove all stores owned by this user; FK cascades wipe products, orders,
  -- employees, payroll, attendance, etc.
  delete from public.tenants where owner_id = uid;
  -- Remove the account itself (auth.identities / sessions cascade from here).
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
