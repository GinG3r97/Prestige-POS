-- Core tenant data + owner PIN. Designed to live alongside Supabase Auth:
-- every row is scoped to auth.uid() via RLS, the PIN is bcrypt-hashed, and
-- verification goes through SECURITY DEFINER RPCs that track failed attempts.

create extension if not exists pgcrypto;

-- ── tenants ─────────────────────────────────────────────────────────────
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  business_name text not null,
  address text not null default '',
  currency text not null default 'PHP',
  timezone text not null default 'Asia/Manila',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index tenants_owner_idx on public.tenants(owner_id);

-- ── branches ────────────────────────────────────────────────────────────
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create index branches_tenant_idx on public.branches(tenant_id);

-- ── owner_pins ──────────────────────────────────────────────────────────
-- Bcrypt-hashed 4-digit owner PIN, one row per tenant. failed_attempts +
-- locked_until throttle brute-force attempts (5 misses → 5-minute lockout).
create table public.owner_pins (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

-- ── RLS ─────────────────────────────────────────────────────────────────
alter table public.tenants enable row level security;
alter table public.branches enable row level security;
alter table public.owner_pins enable row level security;

create policy "owner reads own tenants"
  on public.tenants for select
  using (auth.uid() = owner_id);

create policy "owner inserts own tenants"
  on public.tenants for insert
  with check (auth.uid() = owner_id);

create policy "owner updates own tenants"
  on public.tenants for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "owner deletes own tenants"
  on public.tenants for delete
  using (auth.uid() = owner_id);

create policy "owner reads own branches"
  on public.branches for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner inserts own branches"
  on public.branches for insert
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner updates own branches"
  on public.branches for update
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner deletes own branches"
  on public.branches for delete
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own pin"
  on public.owner_pins for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own pin"
  on public.owner_pins for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

-- ── RPC: set_owner_pin ──────────────────────────────────────────────────
-- Hashes p_pin with bcrypt and upserts into owner_pins. Caller must own the
-- tenant. Resets failed-attempt counter on every successful set.
create or replace function public.set_owner_pin(
  p_tenant_id uuid,
  p_pin text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
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
  values (p_tenant_id, crypt(p_pin, gen_salt('bf', 10)), 0, null, now())
  on conflict (tenant_id) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null,
        updated_at = now();
end;
$$;

revoke execute on function public.set_owner_pin(uuid, text) from public;
revoke execute on function public.set_owner_pin(uuid, text) from anon;
grant execute on function public.set_owner_pin(uuid, text) to authenticated;

-- ── RPC: verify_owner_pin ───────────────────────────────────────────────
-- Returns true on match, false on miss. Locks the PIN for 5 minutes after
-- 5 consecutive misses. Raises if locked.
create or replace function public.verify_owner_pin(
  p_tenant_id uuid,
  p_pin text
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
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

  v_ok := (v_row.pin_hash = crypt(p_pin, v_row.pin_hash));

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

revoke execute on function public.verify_owner_pin(uuid, text) from public;
revoke execute on function public.verify_owner_pin(uuid, text) from anon;
grant execute on function public.verify_owner_pin(uuid, text) to authenticated;
