-- pgcrypto lives in the `extensions` schema on Supabase. Our RPCs set
-- search_path = public, pg_temp for safety, which means `gen_salt` and
-- `crypt` aren't visible. Fix: schema-qualify the calls.

create or replace function public.set_owner_pin(
  p_tenant_id uuid,
  p_pin text
) returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  insert into public.owner_pins (tenant_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (p_tenant_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)), 0, null, now())
  on conflict (tenant_id) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null,
        updated_at = now();
end;
$$;

create or replace function public.verify_owner_pin(
  p_tenant_id uuid,
  p_pin text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_owner uuid;
  v_row public.owner_pins%rowtype;
  v_ok boolean := false;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  select * into v_row from public.owner_pins where tenant_id = p_tenant_id;
  if v_row is null then
    return false;
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception 'PIN locked. Try again later.';
  end if;

  v_ok := (v_row.pin_hash = extensions.crypt(p_pin, v_row.pin_hash));

  if v_ok then
    update public.owner_pins
      set failed_attempts = 0, locked_until = null, updated_at = now()
      where tenant_id = p_tenant_id;
  else
    update public.owner_pins
      set failed_attempts = failed_attempts + 1,
          locked_until = case
            when failed_attempts + 1 >= 5 then now() + interval '5 minutes'
            else null
          end,
          updated_at = now()
      where tenant_id = p_tenant_id;
  end if;

  return v_ok;
end;
$$;
