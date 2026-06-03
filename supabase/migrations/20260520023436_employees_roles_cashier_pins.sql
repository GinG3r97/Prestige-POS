-- Employees + roles + per-cashier PINs.
--
-- ── Design notes ──────────────────────────────────────────────────────
-- * employee_roles is owner-defined per tenant. We seed Owner / Cashier /
--   Inventory Manager on each new tenant (and back-fill existing ones in
--   the DO block at the bottom). Permissions are stored as a jsonb array
--   of route keys ('sell', 'inventory', etc.) matching the Dart AppRoute
--   enum — the role picker UI is the source of truth for which keys are
--   valid; we don't constrain in SQL so the picker can evolve without a
--   migration per change.
--
-- * employees stores money in centavos (integers) — same rule as the rest
--   of the schema. Schedule + documents are jsonb blobs; they're owner-
--   private structured data with no cross-row queries, so a JSON column
--   beats two more join tables.
--
-- * cashier_pins is its own table — copies the owner_pins shape exactly
--   (bcrypt via pgcrypto, 5-attempts-then-5-min lockout). Keeping it
--   separate from employees means: (a) clean RLS scoped to PIN ops only,
--   (b) we can rotate or wipe PINs without touching the employees row,
--   (c) failed_attempts/locked_until aren't mixed into the main record.

-- ── Tables ─────────────────────────────────────────────────────────────

create table public.employee_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  icon_name text,
  -- Route keys this role can access. Matches Dart AppRoute names
  -- (e.g. ["sell","orders","inventory"]). Owner role always gets all
  -- routes — we enforce that in app code, not SQL, so the picker stays
  -- the single source of truth.
  permissions jsonb not null default '[]'::jsonb,
  -- True for roles that ring up sales (Cashier, Owner). Employees with
  -- requires_pin roles must have a row in cashier_pins.
  requires_pin boolean not null default false,
  -- Built-in roles can be renamed but not deleted. Set to true on seed
  -- rows so the UI can hide the delete button.
  is_system boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index employee_roles_tenant_idx
  on public.employee_roles(tenant_id, sort_order);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  role_id uuid references public.employee_roles(id) on delete set null,

  -- Identity
  name text not null,
  -- 'male' | 'female' — we don't store anything outside of that pair
  -- because the only UX consumer is the avatar icon (Icons.man_outlined /
  -- Icons.woman_outlined). If more options are needed later, extend here.
  gender text not null default 'male' check (gender in ('male','female')),

  email text not null default '',
  phone text not null default '',

  -- Employment
  hire_date date not null default current_date,
  status text not null default 'active'
    check (status in ('active','on_leave','terminated')),
  employment_type text not null default 'full_time'
    check (employment_type in ('full_time','part_time','contract','seasonal')),
  compensation_type text not null default 'hourly'
    check (compensation_type in ('hourly','salaried')),
  hourly_rate_cents int not null default 0 check (hourly_rate_cents >= 0),
  monthly_salary_cents int not null default 0 check (monthly_salary_cents >= 0),
  branch_ids uuid[] not null default '{}'::uuid[],

  -- Schedule: array of {weekday: 1..7, start: "HH:mm", end: "HH:mm"}
  schedule jsonb not null default '[]'::jsonb,
  -- Documents: array of {id, name, status, expires_on}
  documents jsonb not null default '[]'::jsonb,

  -- Employee Portal Account — locked / hidden in UI for this turn; the
  -- column lives here so the future feature has a home without another
  -- migration. portal_password_hash will use bcrypt when wired up.
  portal_enabled boolean not null default false,
  portal_gmail text not null default '',
  portal_username text not null default '',
  portal_password_hash text,
  portal_invited_at timestamptz,
  portal_last_login_at timestamptz,

  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index employees_tenant_idx on public.employees(tenant_id);
create index employees_role_idx on public.employees(role_id);

create table public.cashier_pins (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, employee_id)
);

-- ── RLS ────────────────────────────────────────────────────────────────

alter table public.employee_roles enable row level security;
alter table public.employees enable row level security;
alter table public.cashier_pins enable row level security;

create policy "owner reads own employee roles"
  on public.employee_roles for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own employee roles"
  on public.employee_roles for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own employees"
  on public.employees for select
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

create policy "owner manages own employees"
  on public.employees for all
  using (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()
  ));

-- cashier_pins is read-only from client (only RPCs touch it). No SELECT
-- policy = no client can read hashes; UPDATE/DELETE blocked too.
-- The SECURITY DEFINER RPCs below run as the function owner and bypass
-- RLS — we re-check tenant ownership inside the function body.

-- ── RPCs: set/verify cashier PIN (mirrors owner_pin pattern) ──────────

create or replace function public.set_cashier_pin(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_pin text
) returns void
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
begin
  -- Caller must own the tenant.
  if not exists (
    select 1 from public.tenants
    where id = p_tenant_id and owner_id = auth.uid()
  ) then
    raise exception 'not_owner';
  end if;

  -- Employee must belong to the tenant.
  if not exists (
    select 1 from public.employees
    where id = p_employee_id and tenant_id = p_tenant_id
  ) then
    raise exception 'employee_not_found';
  end if;

  -- 4–8 digits only.
  if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then
    raise exception 'invalid_pin_format';
  end if;

  insert into public.cashier_pins
    (tenant_id, employee_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (
    p_tenant_id,
    p_employee_id,
    extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
    0,
    null,
    now()
  )
  on conflict (tenant_id, employee_id) do update set
    pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
    failed_attempts = 0,
    locked_until = null,
    updated_at = now();
end;
$$;

grant execute on function public.set_cashier_pin(uuid, uuid, text) to authenticated;

create or replace function public.verify_cashier_pin(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_pin text
) returns boolean
  language plpgsql
  security definer
  set search_path = public, extensions
as $$
declare
  v_row public.cashier_pins%rowtype;
  v_ok boolean;
begin
  if not exists (
    select 1 from public.tenants
    where id = p_tenant_id and owner_id = auth.uid()
  ) then
    raise exception 'not_owner';
  end if;

  select * into v_row from public.cashier_pins
  where tenant_id = p_tenant_id and employee_id = p_employee_id;

  if not found then
    return false;
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception 'locked';
  end if;

  v_ok := v_row.pin_hash = extensions.crypt(p_pin, v_row.pin_hash);

  if v_ok then
    update public.cashier_pins set
      failed_attempts = 0, locked_until = null, updated_at = now()
    where tenant_id = p_tenant_id and employee_id = p_employee_id;
    return true;
  else
    update public.cashier_pins set
      failed_attempts = failed_attempts + 1,
      locked_until = case
        when failed_attempts + 1 >= 5 then now() + interval '5 minutes'
        else locked_until
      end,
      updated_at = now()
    where tenant_id = p_tenant_id and employee_id = p_employee_id;
    return false;
  end if;
end;
$$;

grant execute on function public.verify_cashier_pin(uuid, uuid, text) to authenticated;

-- ── Back-fill default roles for existing tenants ──────────────────────
-- New tenants get these via completeOnboarding (Flutter side). This block
-- covers tenants that already exist before the migration was applied.
do $$
declare
  v_tenant uuid;
begin
  for v_tenant in (
    select id from public.tenants
    where id not in (select tenant_id from public.employee_roles)
  ) loop
    insert into public.employee_roles
      (tenant_id, name, icon_name, permissions, requires_pin, is_system, sort_order)
    values
      (v_tenant, 'Owner', 'admin_panel_settings_outlined',
       '["dashboard","sell","bookings","sessions","members","orders","reports","employees","payroll","products","inventory","maintenance","settings"]'::jsonb,
       true, true, 10),
      (v_tenant, 'Cashier', 'point_of_sale_outlined',
       '["sell","orders"]'::jsonb,
       true, true, 20),
      (v_tenant, 'Inventory Manager', 'inventory_2_outlined',
       '["inventory","products"]'::jsonb,
       false, true, 30);
  end loop;
end $$;
