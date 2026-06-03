-- Bugfix: routine cashier sign-ins were locking the OWNER PIN.
--
-- The unified PIN login (login_view) probes the owner PIN first for every
-- 4-digit code. Because verify_owner_pin incremented owner_pins.failed_attempts
-- on every mismatch, a cashier signing in with their own (non-owner) 4-digit
-- PIN bumped the owner's brute-force counter — even though their login
-- succeeded. Five such sign-ins tripped a 5-minute "owner PIN locked" with
-- nobody ever mistyping the owner PIN.
--
-- Fix: add p_count_failure. When false (the unified-login probe), a mismatch
-- never increments/locks — it only resets on success. The client charges a
-- single failure at the END of a login only when NOTHING matched, so the
-- screen still resists brute force. Existing 2-arg callers are unchanged
-- (default keeps the old counting behavior).

create or replace function public.verify_owner_pin(
  p_tenant_id uuid,
  p_pin text,
  p_count_failure boolean default true
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
  elsif p_count_failure then
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
