# Plan — Full second-owner access (co-owners run the store on the iPad)

**Goal:** two (or more) emails, one store, **equal full access** — a co-owner can
sign into the **iPad app**, run the POS, and manage the store, exactly like the
primary owner. "2 emails in 1 store."

**Status today (already shipped):** co-owners are *web-portal viewers* — they see
sales + dashboard on the web, added/managed under **Settings → Co-owners**. Table
RLS is still keyed to `owner_id = auth.uid()`, so co-owners hit the "create store"
onboarding if they open the iPad app. This plan closes that gap.

> ⚠️ **Do this AFTER the App Store submission is in.** It rewrites Row-Level
> Security on ~15 live tables. A wrong predicate can lock owners out or leak data
> across stores. Not something to rush before an Apple review.

---

## The 4 workstreams

### 1. One shared access predicate (do this first)
Add a single helper so every policy reads the same rule, instead of hand-editing
15 different `using (...)` clauses:

```sql
create or replace function public.has_tenant_access(p_tenant uuid)
  returns boolean language sql stable security definer
  set search_path to 'public' as $$
  select exists (select 1 from public.tenants t
                 where t.id = p_tenant and t.owner_id = auth.uid())
      or public.is_tenant_member(p_tenant);
$$;
```
(`is_tenant_member` already exists — `20260629130000_tenant_coowners.sql`.)

### 2. Rewrite table RLS to use it
Replace `t.owner_id = auth.uid()` with `public.has_tenant_access(t.id)` (or
`has_tenant_access(tenant_id)` for tenant_id-keyed tables) on **every** core table.
Tables + source migrations (from the access-model audit):

| Table(s) | Migration |
|---|---|
| `tenants` (`auth.uid() = owner_id`) | `20260519191456_tenants_branches_owner_pins.sql:47` |
| `branches`, `owner_pins` | same file `:64-107` |
| `categories`, `sellables`, `tenant_features` | `20260519201320_...:101-152` |
| `employees`, `employee_roles` | `20260520023436_...:116-149` |
| `product_types`, `inventory_items`, `products` | `20260520040818_...:135-157` |
| `orders`, `order_lines`, `payments`, `order_counter`, `audit_log` | `20260519205554_...:131-165` |
| `cashier_shifts` | (same `tenant_id → owner_id` pattern) |

For `tenants` itself: `using (has_tenant_access(id))`. For child tables that join
to tenants: `using (exists (select 1 from tenants t where t.id = <tbl>.tenant_id
and has_tenant_access(t.id)))` — or simplest, `using (has_tenant_access(tenant_id))`.
**Keep INSERT/UPDATE `with check` in sync** so co-owners can write, not just read.
⚠️ Audit for any table added *after* this doc — grep migrations for
`owner_id = auth.uid()` before shipping.

### 3. App: load owned **and** co-owned stores
`lib/app/app_state.dart:199-208` (`_restoreTenantFromDb`) filters
`.eq('owner_id', user.id)`. Change so co-owners resolve their store:
- Simplest: add an RPC `my_tenants()` (SECURITY DEFINER) returning every tenant
  where `owner_id = auth.uid() OR is_tenant_member(id)`, and load from that.
- Then `needsOnboarding` (`app_state.dart:480`) is false for co-owners because
  `_stores` is populated. `_currentTenantDbId` (`:273`) comes from the same rows.

### 4. Relax SECURITY DEFINER write guards
These re-check `owner_id = auth.uid()` server-side and must also accept members:
- `create_paid_order` — `20260520042523_...:45-48` (`v_owner <> auth.uid()`).
- Audit siblings: void / refund / settle-orders, set-PIN, shift open/close, any
  RPC that resolves the tenant from `owner_id = auth.uid()`. Swap the check for
  `if not public.has_tenant_access(p_tenant_id) then raise exception ...`.
- `set_store_geofence` already uses `my_tenant_id()` — good reference.

---

## Decision needed: the owner PIN
Co-owners have no `owner_pins` row for the store. On the iPad, after email sign-in
the app asks for the **owner PIN** (`_ownerPinSet` logic in `app_state.dart`).
Pick one:
- **(A) Shared store PIN** — co-owner uses the same owner PIN. Simplest; the PIN is
  a per-store unlock, not per-person. Recommended.
- **(B) Per-person owner PIN** — each co-owner sets their own `owner_pins` row.
  More work (PIN setup flow for co-owners) but individually revocable.

---

## Test checklist (before shipping)
- [ ] Primary owner: unchanged — signs in, sees only their store, full POS.
- [ ] Co-owner: signs in on iPad → lands on the shared store (NOT onboarding).
- [ ] Co-owner: can ring a sale (`create_paid_order` succeeds), void/refund, edit
      menu, view reports.
- [ ] **Isolation:** co-owner of store A sees ONLY store A — cannot read store B's
      orders/products/employees (run a cross-tenant SELECT as each user).
- [ ] Remove co-owner → their next app load drops the store (no stale access).
- [ ] Staff PIN flow still works for regular employees.
- [ ] Web portal co-owner view still works.

## Rollout & rollback
- Ship as **one migration** (helper + all policy rewrites + RPC guards) so it's
  atomic. Test on a Supabase branch first (`create_branch` → apply → verify
  isolation → `merge_branch`).
- **Rollback:** re-apply the original `owner_id = auth.uid()` policies (keep the
  old `using (...)` text handy). The helper + `tenant_members` can stay.

## Effort
Steps 1, 3, 4 + PIN = moderate (~half day). Step 2 (policy rewrite across ~15
tables, done carefully with isolation tests) is the bulk — budget a focused day
with the cross-tenant test as the gate.
