# Payroll, Attendance & HR System — Architecture & Spec

> A self-contained Philippine-payroll + time-&-attendance + employee-portal module
> built inside the Prestige POS app (Flutter) and its companion web app (Next.js),
> backed by Supabase (Postgres + Auth + RLS). This doc is the source of truth for
> the feature wiring so it can be understood, audited, or rebuilt standalone.

---

## 1. What it does (product scope)

A small-business owner (PH SME: cafés, retail, services) can:

- **Employees & roles** — add staff with a role (Owner/Manager/Cashier/Inventory Manager),
  per-role permission gates, cashier PIN, weekly schedule, pay type & rate, statutory
  contributions, and an optional **Employee Portal** login.
- **Attendance** — staff clock in/out from a phone (web portal) with selfie + geofence
  anti-abuse (Pro), or the owner enters hours manually in a timesheet grid.
- **DTR (Daily Time Record)** — a schedule-aware engine derives, per day:
  regular hours, lateness, undertime, overtime (filed + approved), rest-day,
  night-differential, holidays, paid/unpaid leave, and absences.
- **Filings** — staff file OT / undertime / leave from the portal; the owner approves/rejects.
- **Payroll runs** — generate a pay run for a **semi-monthly cutoff** (15 & 30 or 10 & 25);
  each employee gets an **itemized payslip**: base + OT + premiums (rest-day / night-diff /
  holiday) − undertime − absences − statutory (SSS / PhilHealth / Pag-IBIG) − other.
- **Payslip history** — employees view their finalized/paid payslips in the portal,
  fully itemized, computed identically to the app (to the centavo).
- **Maintenance** — the owner configures payroll rules, leave types, holidays, etc.

PH labor-law concepts implemented: semi-monthly cutoffs, regular/special holidays,
rest-day premium, night differential, lateness grace, undertime, manual OT with a daily
cap, per-employee statutory contributions, paid/unpaid leave. (13th-month pay and BIR
withholding are placeholders — see §11.)

---

## 2. Tech stack & repos

| Layer | Tech | Repo |
|---|---|---|
| POS app (owner-facing) | Flutter / Dart, Provider, `supabase_flutter` | `Prestige-POS` (branch `android-ios`) |
| Web (employee portal + marketing) | Next.js 14 (App Router), TypeScript, Tailwind | `Prestige-POS-Web` (branch `main`) |
| Backend | Supabase: Postgres, Auth (email OTP + Google OAuth), RLS, Edge | — (managed) |

Money is handled in **integer centavos** everywhere (Dart and TS) to avoid float drift;
pesos are only for display.

---

## 3. Data model (Postgres / Supabase)

All tables are tenant-scoped by `tenant_id` and protected by **RLS owner-only** policies
(`EXISTS (SELECT 1 FROM tenants t WHERE t.id = tenant_id AND t.owner_id = auth.uid())`),
except where a `SECURITY DEFINER` function intentionally bridges access for the portal.

### Core HR
- **`tenants`** — the store. `id`, `owner_id` (→ `auth.users`), `store_code` (e.g. `PR-M33TSV`),
  `timezone` (default `Asia/Manila`), `branch_code`, plan/features.
- **`employees`** — `id`, `tenant_id`, `name`, `email`, `phone`, `gender`, `hire_date`,
  `role_id` (→ `employee_roles`), `cashier_pin` (plaintext, by design — owner visibility),
  `schedule` (jsonb: `[{weekday:1..7, start:"HH:mm", end:"HH:mm"}]`, ISO weekday Mon=1),
  `compensation_type` (`hourly|daily|salaried`), `hourly_rate_cents`, `daily_rate_cents`,
  `monthly_salary_cents`, `employment_type` (`full_time|part_time|contract|seasonal`),
  `sss_cents`, `philhealth_cents`, `pagibig_cents` (monthly employee share),
  `portal_enabled`, `portal_gmail` (login email; defaults to `email`), `portal_last_login_at`,
  geofence/selfie config, `status` (`active|terminated`).
- **`employee_roles`** — `id`, `tenant_id`, `name`, `permissions` (jsonb string[]:
  `sell, orders, reports, employees, payroll, attendance, products, inventory,
  maintenance, settings, switch_branch`), `requires_pin`, `is_system`.
- **`owner_pins`** — owner's 4-digit PIN (bcrypt `pin_hash`), brute-force counters
  (`failed_attempts`, `locked_until`).

### Payroll config (Maintenance)
- **`payroll_rules`** — ONE row per tenant. `regular_hours_per_day` (default 8),
  `break_minutes` (unpaid lunch, default 0), `max_overtime_hours_per_day` (0 = no cap),
  `semi_monthly_style` (`fifteen_thirty|ten_twentyfive`),
  `rest_day_multiplier` (1.30), `regular_holiday_multiplier` (2.0),
  `special_holiday_multiplier` (1.30), `night_diff_multiplier` (1.10),
  `night_diff_start_minutes` (1320 = 22:00), `night_diff_end_minutes` (360 = 06:00),
  `deduct_undertime`, `lateness_grace_minutes` (5), `include_13th_month` (placeholder),
  `deduct_sss`, `deduct_philhealth`, `deduct_pagibig`, `withhold_bir` (placeholder).
- **`leave_types`** — `id`, `tenant_id`, `name`, `emoji`, `annual_days` (0 = unlimited),
  `paid` (bool — **drives whether leave credits pay**), `notes`, `is_system`.
- **`holidays`** — `id`, `tenant_id`, `holiday_date`, `name`, `kind` (`regular|special`),
  UNIQUE `(tenant_id, holiday_date)`. (Calendar feature — see §11.)
- **`employment_templates`** — per `employment_type`: default rates +
  `overtime_multiplier` (1.25 typical) — pre-fills the Add-Employee form. The OT multiplier
  is snapshotted onto each payslip at generation.

### Attendance & filings
- **`attendance_punches`** — `tenant_id`, `employee_id`, `kind` (`in|out`),
  `punched_at` (timestamptz), `selfie`, `lat`, `lng`, `within_geofence`, `flagged`.
- **`employee_requests`** — filings. `kind` (`leave|ot|undertime`), `start_date`,
  `end_date` (leave ranges), `leave_type_id`/`leave_type_name`, `hours` (OT/UT),
  `reason`, `status` (`pending|approved|rejected`), `decided_by`, `decided_at`.
- **`time_entries`** — manual/synced daily hours. UNIQUE `(employee_id, entry_date)`,
  `hours` (numeric). The owner's timesheet grid edits these; "Pull from attendance"
  writes straight-time worked hours here.

### Pay runs
- **`payroll_runs`** — `id`, `tenant_id`, `period_start`, `period_end`,
  `kind` (`weekly|biweekly|semi_monthly|monthly`), `status` (`draft|finalized|paid`),
  `paid_at`. UNIQUE `(tenant_id, period_start, period_end, kind)` — **the dedup backstop**.
- **`payslips`** — one per employee per run. Snapshot fields (frozen at generation):
  `employee_id/name/role`, `compensation_type`, `hours_worked` (= credited regular hours,
  incl. paid leave + regular-holiday-not-worked), `hourly_rate`, `daily_rate`,
  `monthly_salary`, `bonus`, `deductions` (manual "other"), `sss`, `philhealth`, `pagibig`
  (monthly amounts, pro-rated at display), `ot_hours`, `undertime_hours`, `late_minutes`,
  `ot_multiplier`, `deduct_undertime`, `restday_hours`/`restday_mult`,
  `nightdiff_hours`/`nightdiff_mult`, `absent_days`, `holiday_premium_hours` (see §11).
  `regular_hours_per_day` is NOT a column — it's re-applied in-app from `payroll_rules`
  after every hydration.

---

## 4. The computation pipeline (the heart of the system)

```
attendance_punches  ─┐
employee schedule    ├─► attendance_day_summary(emp, date)  ── per-DAY jsonb
employee_requests   ─┤        (OT/UT/leave filings)
payroll_rules        ┘
holidays
        │
        ▼  (loop dates in the cutoff)
payroll_dtr_period(emp, start, end)  ── per-PERIOD totals + per-day rows (the DTR)
        │
        ▼  (per employee, at generation)
HrStore._buildSlip → Payslip snapshot ──► payslips table
        │
        ▼
Payslip.grossCentavosFor / netCentavosFor  ── itemized money math
        │
        ├─► App: payroll_view itemized payslip + DTR modal
        └─► Web: portal_my_payslips RPC → payslip-history (re-computes, centavo-exact)
```

### `attendance_day_summary(p_employee uuid, p_date date) → jsonb`
`SECURITY DEFINER`. **Auth guard**: caller must own the tenant (`tenants.owner_id =
auth.uid()`) OR be the employee (`auth.jwt()->>'email' = coalesce(portal_gmail, email)`).
Anon EXECUTE revoked.

Logic, in order:
1. Resolve the employee's schedule for `p_date`'s weekday → `sched_start/end` (minutes
   of day). If `end <= start`, it's an **overnight schedule** → `end += 1440`.
   No schedule that day ⇒ `dayoff`.
2. **Pair punches** for `[p_date, p_date+2)` in the tenant timezone. Sessions start only
   on an IN dated `p_date`; the closing OUT may roll past midnight. `worked` = sum of
   **elapsed minutes** between in/out (handles overnight). `last_out` carried as minute-of-day
   (+1440 if next day).
3. Approved **OT** = `sum(hours)` of approved `ot` filings for the date (manual only —
   never auto-counted from clocking out late).
4. Approved **leave** covering the date → its `leave_types.paid` flag.
5. For a worked scheduled day: `late = max(0, first_in − sched_start)` (zeroed if ≤ grace);
   `undertime = max(0, sched_end − last_out)`. **Paid ceiling**:
   `paid_cap = least(sched_span − break_minutes, regular_hours_per_day×60)`;
   `regular = max(0, paid_cap − late − undertime)`. (So a >8h schedule pays 8h regular;
   the rest is OT only if filed.)
6. **Status** resolution: `restday` (worked day-off) / `dayoff` / `worked` /
   `leave_paid` (credits `sched_min` capped) / `leave_unpaid` / `absent`
   / (holiday variants — §11).
7. **Night differential** minutes within the `[first_in, last_out]` interval ∩ the night
   window (handles the 22:00→06:00 wrap).

Returns: `status, worked_min, regular_min, late_min, undertime_min, ot_min,
restday_min, nightdiff_min, leave_min, leave_paid, leave_name, sched_start/end,
first_in, last_out` (+ holiday fields).

### `payroll_dtr_period(p_employee, p_start, p_end) → jsonb`
`SECURITY DEFINER`, same auth guard. Loops each date, calls `attendance_day_summary`,
and aggregates. Includes every **scheduled** day (worked/leave/absent) in `days[]`
(skips pure days off). Applies the **per-day OT cap** (`max_overtime_hours_per_day`).
`regular_hours` credit = `Σ (regular_min + undertime_min + restday_min + leave_min)`
— undertime is added back so it can be shown as its own deduction line; paid leave +
regular-holiday-not-worked fold into regular (paid at base).

Returns period totals: `regular_hours, ot_hours, undertime_hours, late_minutes,
restday_hours, nightdiff_hours, paid_leave_hours, absent_days, days_present,
worked_hours, days[]` (+ holiday_premium_hours — §11).

### `sync_attendance_to_timesheet(p_start, p_end) → int`
Owner-only. Writes **plain worked straight-time** (`regular_min + restday_min`) into
`time_entries` for each punched day (NOT premium-baked) so the manual grid stays honest;
OT/UT/premiums are kept separate and applied at generation.

---

## 5. Payslip money math (exact — keep app & web identical)

All in integer centavos: `c(pesos) = round(pesos * 100)`.

```
periodsPerMonth = weekly 4.333 · biweekly 2.167 · semi_monthly 2.0 · monthly 1.0
hourlyEquiv     = hourly: hourly_rate
                  daily:  daily_rate / regular_hours_per_day
                  salaried: monthly_salary / 26 / regular_hours_per_day

base            = hourly:   c(hours_worked * hourly_rate)
                  daily:    c((hours_worked / regular_hours_per_day) * daily_rate)
                  salaried: c(monthly_salary / periodsPerMonth)
otPay           = c(ot_hours * hourlyEquiv * ot_multiplier)
restdayPremium  = c(restday_hours * hourlyEquiv * (restday_mult - 1))      // extra above base
nightdiffPrem   = c(nightdiff_hours * hourlyEquiv * (nightdiff_mult - 1))
holidayPremium  = c(holiday_premium_hours * hourlyEquiv)                   // pre-computed extra
gross           = base + otPay + restdayPremium + nightdiffPrem + holidayPremium + c(bonus)

undertime       = deduct_undertime ? c(undertime_hours * hourlyEquiv) : 0
absence         = (salaried) ? c(absent_days * monthly_salary / 26) : 0    // hourly/daily lose hours already
statutory       = c(sss/pm) + c(philhealth/pm) + c(pagibig/pm)             // each rounded then summed
net             = max(0, gross − statutory − undertime − absence − c(deductions))
```

**Centavo-exact parity rule:** the web (`payslip-history.tsx`) and the Flutter
`Payslip` model (`lib/models/payroll.dart`) must round each term independently *before*
summing, in the same order. Any change to one must mirror the other.

---

## 6. Pay periods & cutoffs

The pay run is **always the semi-monthly cutoff** the owner set:
- `fifteen_thirty`: 1–15 and 16–end-of-month.
- `ten_twentyfive`: 11–25 and 26–10 (the latter spans the month end).

The timesheet grid shows a **week** (navigable) for quick entry, but the run + the
tap-an-employee DTR modal use the **cutoff that the displayed week falls in** (anchored
on the week's Thursday). Statutory + monthly salary pro-rate by `periodsPerMonth`
(semi-monthly = ÷2).

---

## 7. App architecture (Flutter)

- **`AppState`** (`lib/app/app_state.dart`) — session/auth/tenant/branch coordinator.
  Splits domain data into per-domain `ChangeNotifier` stores via
  `ChangeNotifierProxyProvider<AppState, XStore>`.
- **`HrStore`** (`lib/app/stores/hr_store.dart`) — employees, roles, payroll_rules,
  leave_types, employment_templates, time_entries, payroll_runs, payslips. Key methods:
  `generatePayrollRun`, `regeneratePayrollRun`, `_buildSlip`, `updatePayslip`,
  `syncTimesheetFromAttendance`, `fetchEmployeeDtr`, `hoursIn`.
- **Models** — `lib/models/payroll.dart` (`Payslip`, `PayrollRun`, `TimeEntry`,
  `PayPeriodKind`, `PayrollStatus`), `payroll_rules.dart` (`PayrollRules`, `LeaveType`,
  `EmploymentTemplate`, `SemiMonthlyStyle`), `employee.dart` (`Employee`,
  `CompensationType`, `phStatutory(salary)` PH-2025 helper).
- **Views** — `features/payroll/payroll_view.dart` (timesheet grid + pay-run pane +
  itemized `_SlipRow` + `_DtrSheet` modal), `features/maintenance/payroll_rules_tab.dart`
  (rails: Hours & rates / Deductions / Leave types / Holidays), `features/employees/*`,
  `features/attendance/*` (RequestsView for OT/UT/leave approvals).
- Auth/PIN: `verifyPin` tries the owner PIN first (→ owner session = all permissions),
  then per-employee cashier PINs (→ that role's permissions). `canAccess(route)` gates nav.

Identity rule: `isOwnerSession = currentOwner != null && currentStaff?.id ==
currentOwner?.id`. The owner is a tenant's `auth.users` row, NOT an employee — the portal
never resolves an owner as an employee even if emails collide.

---

## 8. Web portal (Next.js)

- `app/portal/page.tsx` → `PortalDashboard` (clock in/out, week DTR, file OT/UT/leave,
  leave credits). Store scope comes only from the QR `?store=PR-XXXX`.
- `app/portal/payslips/page.tsx` → `PayslipHistory` (one card per cutoff, expandable,
  fully itemized; finalized/paid only).
- `app/portal/actions.ts` — server actions wrapping the portal RPCs.
- Identity is **always** the signed-in `auth.jwt()->>'email'`; `?store` only narrows.

### Portal RPCs (all `SECURITY DEFINER`, JWT-scoped)
`portal_employee(store)` (resolves the caller→employee, excludes tenant owners),
`portal_me`, `portal_my_summary`, `portal_week`, `portal_my_requests`,
`portal_leave_types`, `portal_leave_credits`, `portal_clock_open`, `portal_punch`,
`file_request`, `decide_request`, `portal_my_payslips`.

---

## 9. Business rules cheat-sheet

| Concept | Rule |
|---|---|
| Overtime | **Manual** — employee files hours, owner approves; only approved OT pays. Capped per day by `max_overtime_hours_per_day`. Paid at `ot_multiplier` (employment template). |
| Undertime | `undertime = sched_end − last_out`. Deducted only if `deduct_undertime`. Shown as a line. |
| Lateness | `first_in − sched_start`, zeroed if ≤ `lateness_grace_minutes`. Reduces regular (no separate line). |
| Regular cap | Regular straight-time ≤ `regular_hours_per_day`; extra needs filed OT. `break_minutes` (unpaid lunch) subtracted. |
| Rest-day | Worked on a scheduled day off → paid at `rest_day_multiplier`. |
| Night diff | Minutes in the night window → premium `(night_diff_multiplier − 1)`. |
| Holidays | `regular`: worked → multiplier; not-worked-scheduled → 100% paid. `special`: worked → multiplier; not-worked → no pay. |
| Leave | Approved + `leave_types.paid` → credits scheduled hours (auto ~8h) into pay. Unpaid → tagged, 0 pay. |
| Absent | Scheduled day, no punch, no leave → 0 pay (hourly/daily lose hours; salaried docked `monthly/26`). |
| Statutory | Per-employee monthly SSS/PhilHealth/Pag-IBIG, gated by tenant toggles, pro-rated by `periodsPerMonth`. PH-2025 auto-suggest from salary. |
| Net floor | Net never goes below ₱0 (uncollectible statutory simply isn't collected that run). |

---

## 10. Security model

- **RLS owner-only** on all tenant tables. The portal reaches data exclusively through
  `SECURITY DEFINER` RPCs that resolve identity from the JWT — never from client input.
- Every `SECURITY DEFINER` function pins `search_path` and guards the caller
  (owner-of-tenant OR the employee themselves). `anon` EXECUTE revoked on sensitive ones.
- `?store` / `p_store` only **narrows** a caller's matched identity; it can never widen it.
- Owner PIN + cashier PINs throttled (5 wrong → lockout). Cashier PINs are plaintext by
  design (owner visibility); owner PIN is bcrypt.
- Duplicate pay runs prevented by a DB UNIQUE constraint (not just the app cache guard).

---

## 11. Status & known gaps (as of this writing)

Implemented & live: itemized payslips, OT (manual+capped), undertime (+toggle), paid/unpaid
leave, absences (incl. salaried docking), per-employee statutory, rest-day & night-diff
premiums, semi-monthly cutoffs, overnight shifts, OT-after-regular-hours + unpaid break,
employee payslip portal (centavo-exact), security hardening, dup-run constraint.

In progress / deferred:
- **Holiday calendar** — `holidays` table exists; the engine (`attendance_day_summary` /
  `payroll_dtr_period`), `payslips.holiday_premium_hours`, the Maintenance Holidays UI,
  and app/web payslip lines are the remaining wiring. `regular_holiday_multiplier` /
  `special_holiday_multiplier` are configured but only fully paid once this lands.
- **13th-month pay** and **BIR withholding** — toggles exist, labeled "coming soon";
  need accrual logic + PH tax tables.
- **Re-generate atomicity** — `regeneratePayrollRun` deletes then inserts slips in two
  round-trips; should be a single transactional RPC.
- **Server RPCs in git** — `attendance_day_summary`, `payroll_dtr_period`, `portal_*`
  live only in the DB; capture them as committed migrations for reproducibility.
- **Mixed manual+attendance** — once any punch exists for an employee in a period, the
  manual grid hours for that employee are ignored period-wide (attendance is authoritative).

---

## 12. Build / deploy notes

- App: `flutter build apk --release` (JAVA_HOME = Android Studio jbr), then
  `adb install -r`. After deploy, smoke-test via ADB (navigate key screens + scan logcat
  for `E/flutter`/`RenderFlex`); never push real transactions.
- Web: stop any `next start` on :3000 before `npm run build` (rebuilding under a live
  server corrupts `.next`).
- DB changes go through Supabase migrations. The auth guard means service-role SQL can't
  call the guarded RPCs directly — set `request.jwt.claims` to the owner to test.
