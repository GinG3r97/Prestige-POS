-- Owner-managed co-owners from the POS app. The app is signed in as the
-- store's owner (owner_id = auth.uid()), so these resolve the tenant from
-- the caller and only the primary owner (or an admin) may manage co-owners.

create or replace function public.tenant_members_list()
  returns table(email text, role text, created_at timestamptz)
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select m.email, m.role, m.created_at
  from public.tenant_members m
  where m.tenant_id = (select id from public.tenants where owner_id = auth.uid() limit 1)
  order by m.created_at;
$function$;

create or replace function public.tenant_member_add(p_email text, p_role text default 'owner')
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
as $function$
declare
  v_tid uuid;
  v_email text := lower(trim(p_email));
begin
  v_tid := (select id from public.tenants where owner_id = auth.uid() limit 1);
  if v_tid is null then raise exception 'NOT_OWNER'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'BAD_EMAIL'; end if;
  if v_email = lower(coalesce((select email from auth.users where id = auth.uid()), '')) then
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
  set search_path to 'public'
as $function$
declare v_tid uuid;
begin
  v_tid := (select id from public.tenants where owner_id = auth.uid() limit 1);
  if v_tid is null then raise exception 'NOT_OWNER'; end if;
  delete from public.tenant_members
   where tenant_id = v_tid and lower(email) = lower(trim(p_email));
  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.tenant_members_list() to authenticated;
grant execute on function public.tenant_member_add(text, text) to authenticated;
grant execute on function public.tenant_member_remove(text) to authenticated;
