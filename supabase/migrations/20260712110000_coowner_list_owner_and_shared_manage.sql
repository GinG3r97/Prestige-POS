-- Co-owners UX polish (web-portal tier — NOT full iPad access yet):
--   1. tenant_members_list() now also returns the PRIMARY OWNER as the first
--      row (is_primary = true) so the app can show "Owner + co-owners" in one
--      list. Resolves the store via my_tenant_id() so a signed-in co-owner
--      (web portal) sees the same list, not just the primary owner.
--   2. tenant_member_add / tenant_member_remove now resolve the store via
--      my_tenant_id() as well, so a co-owner can also add/remove co-owners —
--      "co-owner can add another owner". The primary owner can never be added
--      as a member (ALREADY_OWNER) and is not stored in tenant_members, so
--      they can't be removed here.
--
-- This does NOT grant iPad POS/data access — table RLS is still owner_id-keyed.
-- (See the planned "full second owner" migration for that.)

drop function if exists public.tenant_members_list();

create or replace function public.tenant_members_list()
  returns table(email text, role text, created_at timestamptz, is_primary boolean)
  language sql
  stable
  security definer
  set search_path to 'public', 'auth'
as $function$
  with tid as (select public.my_tenant_id() as id)
  select u.email::text, 'owner'::text, t.created_at, true
    from public.tenants t
    join auth.users u on u.id = t.owner_id
   where t.id = (select id from tid)
  union all
  select m.email, m.role, m.created_at, false
    from public.tenant_members m
   where m.tenant_id = (select id from tid)
  order by 4 desc, 3;  -- is_primary desc, created_at (positional: aliases not visible through UNION)
$function$;

create or replace function public.tenant_member_add(p_email text, p_role text default 'owner')
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public', 'auth'
as $function$
declare
  v_tid uuid;
  v_email text := lower(trim(p_email));
  v_owner_email text;
begin
  v_tid := public.my_tenant_id();
  if v_tid is null then raise exception 'NOT_OWNER'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'BAD_EMAIL'; end if;
  select lower(u.email) into v_owner_email
    from public.tenants t join auth.users u on u.id = t.owner_id
   where t.id = v_tid;
  if v_email = coalesce(v_owner_email, '') then
    raise exception 'ALREADY_OWNER';
  end if;
  insert into public.tenant_members (tenant_id, email, role)
  values (v_tid, v_email, coalesce(nullif(p_role, ''), 'owner'))
  on conflict (tenant_id, email) do update set role = excluded.role;
  return jsonb_build_object('ok', true, 'email', v_email);
end;
$function$;

create or replace function public.tenant_member_remove(p_email text)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public', 'auth'
as $function$
declare v_tid uuid;
begin
  v_tid := public.my_tenant_id();
  if v_tid is null then raise exception 'NOT_OWNER'; end if;
  delete from public.tenant_members
   where tenant_id = v_tid and lower(email) = lower(trim(p_email));
  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.tenant_members_list() to authenticated;
grant execute on function public.tenant_member_add(text, text) to authenticated;
grant execute on function public.tenant_member_remove(text) to authenticated;
