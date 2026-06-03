-- Enforce that no two PINs inside a tenant share the same 4-digit code.
-- Since each PIN is bcrypt-hashed with a unique salt, we can't use a
-- UNIQUE constraint — instead we verify the new plaintext against every
-- other stored hash via bcrypt's `crypt(plain, full_hash) = full_hash`
-- check (the same idiom the verify_*_pin RPCs use).
--
-- Collisions surface as a `PIN_TAKEN` exception so the Dart client can
-- match on the prefix and show a plain-English toast naming the holder.

create or replace function public.set_owner_pin(p_tenant_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = 'public', 'extensions', 'pg_temp'
as $$
declare
  v_owner uuid;
  v_collision_name text;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  select e.name
    into v_collision_name
  from public.cashier_pins cp
  join public.employees e on e.id = cp.employee_id
  where cp.tenant_id = p_tenant_id
    and extensions.crypt(p_pin, cp.pin_hash) = cp.pin_hash
  limit 1;
  if v_collision_name is not null then
    raise exception 'PIN_TAKEN: that PIN is already used by % — please pick a different 4-digit code.', v_collision_name;
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


create or replace function public.set_cashier_pin(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = 'public', 'extensions', 'pg_temp'
as $$
declare
  v_owner uuid;
  v_collision_name text;
  v_owner_collision boolean;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  select extensions.crypt(p_pin, op.pin_hash) = op.pin_hash
    into v_owner_collision
  from public.owner_pins op
  where op.tenant_id = p_tenant_id;
  if v_owner_collision then
    raise exception 'PIN_TAKEN: that PIN is already used by the store owner — please pick a different 4-digit code.';
  end if;

  select e.name
    into v_collision_name
  from public.cashier_pins cp
  join public.employees e on e.id = cp.employee_id
  where cp.tenant_id = p_tenant_id
    and cp.employee_id <> p_employee_id
    and extensions.crypt(p_pin, cp.pin_hash) = cp.pin_hash
  limit 1;
  if v_collision_name is not null then
    raise exception 'PIN_TAKEN: that PIN is already used by % — please pick a different 4-digit code.', v_collision_name;
  end if;

  insert into public.cashier_pins (tenant_id, employee_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (
    p_tenant_id,
    p_employee_id,
    extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
    0, null, now()
  )
  -- PK on cashier_pins is composite (tenant_id, employee_id) — the
  -- conflict target must match that exact column set.
  on conflict (tenant_id, employee_id) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null,
        updated_at = now();
end;
$$;
