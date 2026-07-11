# Prestige Café — Master Flow

_Complete map of the app's flows: account creation → PIN, existing-account login,
every server-side shield, and product → checkout → reports. Last updated 2026-07-11._

---

## 1) First run: new account → first sale

The app's `main.dart` picks the screen from `AppState`, in this exact order:

| State check | Screen | What happens |
|---|---|---|
| `!hasAccount` | **Welcome** | Choose _Sign up_ or _Sign in_ |
| sign up | **Email → OTP** | Supabase email OTP; account (`auth.users`) created |
| `needsOnboarding` (account, no store) | **Onboarding** | Enter business name → creates the **tenant** |
| _(DB triggers on tenant insert)_ | _automatic_ | `trg_set_store_code` (BEFORE INSERT) generates the `store_code` (PR-XXXXXX) · `trg_seed_trial_subscription` (AFTER INSERT) creates the **Free/trial** subscription · `tenants_features_trigger` (AFTER INSERT) creates the features row |
| _(app-side, in `completeOnboarding`)_ | _automatic_ | Seeds default modifier groups (Size / Temperature / Strength) + starter inventory categories (Drinks / Foods / Items) — idempotent via unique constraints |
| `needsToSetPin` (store, no owner PIN) | **Set PIN** | Owner sets a 4-digit PIN (`set_owner_pin`, hashed) |
| `!isAuthenticated` | **Login (PIN)** | Enter PIN to unlock the till |
| else | **Shell** | The POS (Sell, Products, Reports, …) |

**Path:** Welcome → Sign up → Verify email → Onboard business → Set owner PIN → Enter PIN → Selling.

---

## 2) Existing account (master login flow)

- **Same device, session cached:** open app → **Enter PIN** → Shell. (Supabase session persists; the PIN is the daily local gate.)
- **New device / signed out:** Welcome → Sign in → Email OTP → (store + owner PIN already exist) → Enter PIN → Shell.
- **Staff:** the owner's device stays signed in; each cashier taps **their own PIN** (`employees.cashier_pin`) on the Login screen → their **role** decides which nav tabs/actions show.
- **Forgot PIN:** _Forgot PIN_ → re-verify by email OTP → set a new PIN.
- **Co-owner:** a second email in `tenant_members` gets its own web-portal login to the same store.

---

## 3) The shields (all server-enforced — cannot be bypassed by the client)

1. **Tenant isolation** — RLS is enabled on **all 42** public tables. Four of them (`app_admins`, `cashier_pins`, `clockout_reminders`, `upgrade_requests`) intentionally have **zero policies** = deny-all; they are reachable only through SECURITY DEFINER RPCs / service role.
2. **Login shield** — `mobile_login_check` / `lookup_store`: store code must exist **and** the email must belong to that store — owner, co-owner (`tenant_members`), or staff (`employees` with `portal_enabled = true`) — before an OTP is sent.
3. **PIN gates** — owner PIN is **hashed** (`owner_pins.pin_hash` via `crypt`) with **lockout** (`failed_attempts` + `locked_until`, enforced inside `verify_owner_pin`); per-cashier PINs (`employees.cashier_pin`) are plaintext **by design** so the owner can view them.
4. **Tier caps (the plan shield)** — `plan_limits` → `tenant_cap()` → `enforce_plan_cap()` BEFORE-INSERT triggers on **products, categories, employees, inventory_items, branches** (all 5 live + enabled). Over-cap inserts are **rejected in the DB**.
5. **Daily order cap + subscription gate** — inside `create_paid_order`: blocks past the plan's orders/day, and blocks selling entirely if the subscription is **paused/canceled**.
6. **Branch billing** — Pro = **1 branch + paid `extra_branches`**; only Pro can open more; enforced in `tenant_cap('branches')`.
7. **Refund/void authorization** — per-line/whole-order reversals require an **authorizer PIN** (`_authorize_refund_pin`).
8. **RPC lockdown** — SECURITY DEFINER functions revoked from `anon`; trigger functions (`enforce_plan_cap`, `seed_trial_subscription`) made **non-callable over the API**.
9. **Apple/Play compliance** — no prices or purchase buttons in-app; buying happens on the web ("web sells, app reflects").

**Added / hardened 2026-07-11:** branch-billing shield · captured the whole tier shield into version-controlled migrations · trigger-function API lockdown · softened cap wording to be store-approval-safe.

### Plan caps (source of truth: `plan_limits`)

| | Free (trial) | Basic | Pro |
|---|---|---|---|
| Orders / day | 20 | 100 | Unlimited |
| Staff | 2 | 5 | Unlimited |
| Products | 25 | 100 | Unlimited |
| Categories | 6 | 15 | Unlimited |
| Inventory items | 15 | 60 | Unlimited |
| Branches | 1 | 1 | 1 + paid add-ons |

---

## 4) Product → checkout → reports

**Add product** → `products` insert → `cap_products` trigger checks the plan (Free = 25) → allowed, or blocked with a friendly message.

**Sell → checkout**

1. Tap items → **cart** (sizes, add-ons, custom price, discounts).
2. **Tender** (Cash / GCash / QR Ph / Bank + reference).
3. `create_paid_order` RPC runs the gauntlet: **idempotency** (`client_request_id`) → **subscription active?** → **under daily order cap?** → inserts `orders` + `order_lines` + `payments` → **auto-deducts recipe inventory** → writes `audit_log`.
4. **Receipt** prints (Bluetooth thermal) with a **re-print** option.
5. **Pay Later (tabs):** order stays `open`; settling routes back through Sell and pays normally.
6. **Void / Refund:** `reverse_order_line` (one item) or whole-order — authorizer PIN, **restocks** ingredients, **recomputes the order total** to net.

**Reports**

- Pulls **all** orders in the range (paginated — no 5000-row truncation).
- Counts only **paid** orders and **active** lines (reversed/refunded lines never inflate items/categories/top-sellers); payment mix reconciles to net revenue.
- Lenses: Sales, Products, Categories, Peak hours, Cashiers, Payments, Refunds, Inventory.
- Date presets (Today / Yesterday / This week / 7d / 30d / This month / Last month) + a fixed **Custom range** picker, compare-to-previous, and CSV export.

---

## Audit trail (deep audit 2026-07-11)

Every claim in this document was verified against the **live database** (pg_trigger,
pg_proc source, pg_policy, information_schema) and the app code, not from memory:

- ✅ Routing order confirmed in `lib/main.dart` (welcome → hydrating → onboarding → set-PIN → locking → login → settling → shell).
- ✅ All 3 tenant-insert DB triggers live (`trg_set_store_code`, `trg_seed_trial_subscription`, `tenants_features_trigger`); modifier/inventory seeding confirmed app-side in `completeOnboarding`.
- ✅ RLS enabled on 42/42 public tables; the 4 zero-policy tables are deny-all by design.
- ✅ `mobile_login_check` source confirmed: store code + email must match owner / `tenant_members` / portal-enabled employee.
- ✅ `owner_pins` schema = `pin_hash`, `failed_attempts`, `locked_until`; `verify_owner_pin`/`set_owner_pin` use `crypt` + lockout.
- ✅ Forgot-PIN = fresh email OTP → `OtpEntryView` → `SetPinView` (`lib/features/pin/forgot_pin_view.dart`).
- ✅ `create_paid_order` has **exactly one signature** (16 args — no PostgREST PGRST203 overload risk) and contains all five gates: idempotency (`client_request_id`), subscription pause/cancel gate, daily order cap, recipe deduction, audit log.
- ✅ `reverse_order_line` / `refund_order` / `void_order` all require the authorizer PIN, restock ingredients, and write `audit_log`.
- ✅ `enforce_plan_cap` triggers live + enabled on all 5 capped tables; `plan_limits` values match the table above; branch add-on activation tested end-to-end (cap 1 → 3 with 2 paid branches) and rolled back.
- ⚠️ Known minor gap: `settle_orders` (Pay Later settlement) does **not** write an `audit_log` entry — the order creation did, but the settle action itself is unlogged.
- ℹ️ The daily order cap counts **all** orders created today (open + voided included), which makes Pay Later unable to dodge the cap — intentional anti-abuse.

## Related docs

- Payroll & HR: `docs/PAYROLL_HR_SYSTEM.md`
- Tier enforcement migrations: `supabase/migrations/20260711120000_capture_plan_cap_shield.sql`, `..._per_branch_billing.sql`, `..._branch_addon_billing.sql`
