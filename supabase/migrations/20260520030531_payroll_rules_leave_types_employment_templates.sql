-- Payroll persistence + employment templates.
--
-- Three new tables:
--   • payroll_rules        — one row per tenant, holds tenant-wide rules
--                            (standard hours, holiday/night-diff multipliers,
--                            undertime, government deductions).
--   • leave_types          — many per tenant; named leave buckets (SIL, VL, SL).
--   • employment_templates — one row per (tenant, employment_type). Drives
--                            auto-populate in the Add Employee modal. Each
--                            template owns: compensation_type, default rates,
--                            standard-OT multiplier override, set of leave
--                            types that this employment type can avail.
--
-- We also:
--   • add `daily` as a compensation_type on employees (new CHECK), plus a
--     new daily_rate_cents column to mirror hourly/monthly storage.
--   • back-fill default rows so every existing tenant comes online with
--     sensible PH defaults — same values the in-memory mock used.

-- ── 1.  Allow `daily` as a compensation type on employees ────────────
alter table public.employees
  drop constraint if exists employees_compensation_type_check;
alter table public.employees
  add constraint employees_compensation_type_check
  check (compensation_type in ('hourly','daily','salaried'));

alter table public.employees
  add column if not exists daily_rate_cents int not null default 0
    check (daily_rate_cents >= 0);

-- ── 2.  payroll_rules — tenant-wide rules ────────────────────────────
create table public.payroll_rules (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  regular_hours_per_day numeric(5,2) not null default 8 check (regular_hours_per_day > 0),
  rest_day_multiplier numeric(5,3) not null default 1.30 check (rest_day_multiplier >= 1),
  regular_holiday_multiplier numeric(5,3) not null default 2.00 check (regular_holiday_multiplier >= 1),
  special_holiday_multiplier numeric(5,3) not null default 1.30 check (special_holiday_multiplier >= 1),
  night_diff_multiplier numeric(5,3) not null default 1.10 check (night_diff_multiplier >= 1),
  night_diff_start_minutes int not null default 1320 check (night_diff_start_minutes between 0 and 1439),
  night_diff_end_minutes int not null default 360 check (night_diff_end_minutes between 0 and 1439),
  deduct_undertime boolean not null default true,
  lateness_grace_minutes int not null default 5 check (lateness_grace_minutes >= 0),
  include_13th_month boolean not null default true,
  deduct_sss boolean not null default true,
  deduct_philhealth boolean not null default true,
  deduct_pagibig boolean not null default true,
  withhold_bir boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ── 3.  leave_types — owner-defined leave buckets ────────────────────
create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  emoji text not null default '🌴',
  icon_name text,
  -- 0 = unlimited / no cap (used for maternity etc.).
  annual_days int not null default 5 check (annual_days >= 0),
  paid boolean not null default true,
  notes text not null default '',
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create index leave_types_tenant_idx on public.leave_types(tenant_id, sort_order);

-- ── 4.  employment_templates — one per (tenant, employment_type) ─────
create table public.employment_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employment_type text not null
    check (employment_type in ('full_time','part_time','contract','seasonal')),
  compensation_type text not null default 'hourly'
    check (compensation_type in ('hourly','daily','salaried')),
  -- Defaults applied to new employees of this employment type. Owner can
  -- still override per-employee in the Add Employee modal.
  default_hourly_rate_cents int not null default 0 check (default_hourly_rate_cents >= 0),
  default_daily_rate_cents int not null default 0 check (default_daily_rate_cents >= 0),
  default_monthly_salary_cents int not null default 0 check (default_monthly_salary_cents >= 0),
  -- Standard OT multiplier (the 1.25 / 1.30 type rate). Only standard OT
  -- moves per-employment-type for now — labor-law multipliers (rest day,
  -- holidays, night diff) stay global in payroll_rules.
  overtime_multiplier numeric(5,3) not null default 1.25 check (overtime_multiplier >= 1),
  -- IDs of leave_types this employment type can avail. Storing as uuid[]
  -- (matches the existing branch_ids pattern on employees) — the picker is
  -- the source of truth; deleted leave types simply drop out of the picker.
  leave_type_ids uuid[] not null default '{}'::uuid[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, employment_type)
);

create index employment_templates_tenant_idx
  on public.employment_templates(tenant_id);

-- ── RLS — owner-only across all three tables ─────────────────────────
alter table public.payroll_rules enable row level security;
alter table public.leave_types enable row level security;
alter table public.employment_templates enable row level security;

create policy "owner reads own payroll rules"
  on public.payroll_rules for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own payroll rules"
  on public.payroll_rules for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner reads own leave types"
  on public.leave_types for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own leave types"
  on public.leave_types for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner reads own employment templates"
  on public.employment_templates for select
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));
create policy "owner manages own employment templates"
  on public.employment_templates for all
  using (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t
    where t.id = tenant_id and t.owner_id = auth.uid()));

-- ── 5.  Back-fill default rows for existing tenants ──────────────────
-- New tenants get these via completeOnboarding (Flutter side). This block
-- covers tenants that already exist before the migration was applied.
do $$
declare
  v_tenant uuid;
  v_sil uuid;
  v_vl uuid;
  v_sl uuid;
begin
  for v_tenant in (
    select id from public.tenants
    where id not in (select tenant_id from public.payroll_rules)
  ) loop
    insert into public.payroll_rules (tenant_id) values (v_tenant);

    insert into public.leave_types
      (tenant_id, name, emoji, icon_name, annual_days, paid, notes, sort_order)
    values
      (v_tenant, 'Service Incentive Leave', '🌴', 'park_outlined',
       5, true, 'Mandatory PH SIL — convertible to cash if unused.', 10)
    returning id into v_sil;
    insert into public.leave_types
      (tenant_id, name, emoji, icon_name, annual_days, paid, notes, sort_order)
    values
      (v_tenant, 'Vacation Leave', '🏖', 'beach_access_outlined',
       10, true, '', 20)
    returning id into v_vl;
    insert into public.leave_types
      (tenant_id, name, emoji, icon_name, annual_days, paid, notes, sort_order)
    values
      (v_tenant, 'Sick Leave', '🤒', 'sick_outlined',
       7, true, '', 30)
    returning id into v_sl;

    -- Templates: regular full-timers get the full leave set; part-time +
    -- contract default to SIL only; seasonal nothing. Owner edits later.
    insert into public.employment_templates
      (tenant_id, employment_type, compensation_type,
       default_monthly_salary_cents, overtime_multiplier, leave_type_ids)
    values
      (v_tenant, 'full_time', 'salaried',
       2800000, 1.25, array[v_sil, v_vl, v_sl]);
    insert into public.employment_templates
      (tenant_id, employment_type, compensation_type,
       default_hourly_rate_cents, overtime_multiplier, leave_type_ids)
    values
      (v_tenant, 'part_time', 'hourly',
       12000, 1.25, array[v_sil]);
    insert into public.employment_templates
      (tenant_id, employment_type, compensation_type,
       default_daily_rate_cents, overtime_multiplier, leave_type_ids)
    values
      (v_tenant, 'contract', 'daily',
       80000, 1.25, array[v_sil]);
    insert into public.employment_templates
      (tenant_id, employment_type, compensation_type,
       default_hourly_rate_cents, overtime_multiplier, leave_type_ids)
    values
      (v_tenant, 'seasonal', 'hourly',
       11000, 1.25, '{}'::uuid[]);
  end loop;
end $$;
