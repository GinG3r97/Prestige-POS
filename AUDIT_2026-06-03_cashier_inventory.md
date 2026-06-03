# Cashier · Coffee/Food Inventory · Voids · Z-Reading — Focused Audit (2026-06-03)

Scope: the cashier ringing up coffee/food, how that moves inventory, what happens
when a cashier punches wrong, end-of-day cash-up, and a POS feature-gap review.
Method: 3 parallel deep-reads + direct verification of every critical claim.

Severity: 🔴 fix before real use · 🟠 fix soon · 🟡 quality/gap · 🟢 polish

---

## A. THE WRONG-PUNCH PROBLEM (your #1 ask) — 🔴 NOT SOLVED TODAY

**Before payment** the cashier CAN fix mistakes: minus button removes/decrements a
line, the trash icon clears the cart ([cart_panel.dart:37,110](lib/features/cart/cart_panel.dart#L37),
[cart.dart:170](lib/models/cart.dart#L170)). That part is fine.

**After payment there is NO working correction at all:**
- The **Refund** button is a dead handler — `onPressed: () {}` ([orders_view.dart:513](lib/features/orders/orders_view.dart#L513)).
  So is **Reprint** ([495](lib/features/orders/orders_view.dart#L495)) and **Email receipt** ([531](lib/features/orders/orders_view.dart#L531)).
- A **`voidOrder()`** method exists ([app_state.dart:3757](lib/app/app_state.dart#L3757)) and a `void_order`
  database function exists — **but no screen ever calls it.** It is dead code.
- There is **no `refundOrder`** anywhere — no method, no database function.
- Voiding/refunding **does NOT put stock back.** Deduction is one-way. The DB even
  has a `recipe_deducted` flag reserved for reversing, but nothing uses it.

**What this means at the counter:** if a cashier bills a Large Latte instead of a
Small, or rings someone twice, there is no in-app way to reverse it. The sale stays
in reports, the cash is "expected," and the ingredients stay deducted. Today the
only workaround is editing the database by hand.

**What a cafe POS needs here (industry standard):**
1. **Void** (before money is banked / same shift) — cancels the order, reason
   required, restocks ingredients, writes who/why to the audit log.
2. **Refund** (after the fact) — returns money by tender, reason required, restocks,
   audit log. Support **partial / per-line** refund, not just whole-order.
3. **Manager approval (PIN)** to authorize a void/refund — prevents cashier theft via
   fake refunds. This is the single most-abused hole in cafe POS.
4. **Reason codes** (wrong item, customer changed mind, double charge, comp/waste).
5. **Reprint** the corrected receipt.

The backend is ~60% there (void RPC + status columns + audit log). The missing work
is: a refund RPC, an inventory-restock step on void/refund, and wiring three buttons
to a confirm-dialog + manager-PIN.

---

## B. Z-READING / END-OF-DAY CASH-UP (your #2 ask) — 🔴 COMPLETELY ABSENT

Searched the entire codebase for `z-read`, `x-read`, `cash drawer`, `shift`, `till`,
`opening_float`, `closing` — **zero results.** None of it exists.

What exists today is a **Reports** screen ([reports_view.dart](lib/features/reports/reports_view.dart)) that shows
read-only KPI cards: total sales, order count, top items, sales by hour, sales by
payment method, cashier leaderboard, and a refunds/voids list. Useful, but it is a
dashboard — **not a cash-up.**

**Missing — and every cafe needs these to balance the drawer:**
- **Shift / till session**: cashier opens a shift with an **opening float** (starting
  cash), closes it with a **counted amount**. No such concept exists.
- **X-Reading**: a mid-shift snapshot (does not close the shift).
- **Z-Reading**: the end-of-shift report that **closes** the period and shows:
  gross sales, number of transactions, **voids**, **refunds**, **discounts/comps**,
  sales per **payment method**, **cash expected in drawer** vs **cash counted**, and
  the **over/short** difference. In many countries the Z-number is also a legal
  sequential counter.
- **Drawer reconciliation**: expected cash = opening float + cash sales − cash
  refunds − paid-outs; cashier counts, system shows over/short.

You already capture the raw ingredients for this — payment method, tendered, change
([order.dart:98](lib/models/order.dart#L98)) — so a Z-read is mostly aggregation + a new
`shifts` table. The blocker is there's no shift to scope "this drawer, this cashier,
since open."

---

## C. COFFEE/FOOD INVENTORY — WHAT'S MISSING OR WRONG

### 🔴 C1. Deleting an inventory item silently breaks recipes
`removeInventoryItem()` ([app_state.dart:2704](lib/app/app_state.dart#L2704)) deletes with no
cascade/guard. Products that used that ingredient keep a dangling reference. The
product **still sells**, but `expandRecipe()` **silently skips** the missing item
([app_state.dart:1800](lib/app/app_state.dart#L1800)) — so **no stock is deducted and nobody is
warned.** Over weeks your stock counts drift away from reality with no trace.

### 🔴 C2. "Large" can oversell — availability checks the wrong amount
The sell grid hides items via `canFulfillOne()` ([app_state.dart:1853](lib/app/app_state.dart#L1853)),
but it only checks the **base recipe** — it ignores size **multipliers** and
**add-ons**. A drink whose Large pulls 2× beans can show as available when only 1×
is in stock. (The final tender check `validateCartStock()` does expand modifiers, so
it usually catches it at payment — but the grid lies until then, and orphan refs
slip through both checks.)

### 🔴 C3. Stock-adjustment reason is thrown away — no movement ledger
When you record Waste / Spillage / Theft / Recount, the **reason is shown in a toast
then discarded** — it is never saved ([adjustStock at app_state.dart:2718](lib/app/app_state.dart#L2718)).
Only the single `current_stock` number is overwritten. There is **no stock-movement
history**, so you can never answer "where did 2 L of milk go?" or "who recounted
this?" This is the inventory equivalent of having no receipts.

### 🔴 C4. Base price input loses centavos
[products_view.dart:1032](lib/features/products/products_view.dart#L1032) loads the price field with
`(centavos / 100).toStringAsFixed(0)` — **integer pesos only**. Edit a ₱123.45 item
and the field shows `123`; save and it becomes ₱123.00. Every edit quietly rounds
away centavos. (Option-delta field [1084](lib/features/products/products_view.dart#L1084) has the same display bug.)

### 🟠 C5. Recipe editor accepts 0-quantity and mismatched units
No validation that a recipe quantity is > 0 or that the ingredient's unit family
(mass/volume/count) makes sense. You can save "0 g coffee" or attach a "pieces"
item where grams are expected; it just under/over-deducts later.

### 🟡 C6. Cashier is blind to stock status
Out-of-stock items just vanish from the grid with no "sold out" badge, and there's
no low-stock warning on the sell screen — only on the Inventory page. No COGS/margin
is computed anywhere, though `cost_per_unit` is captured, so profit-per-product is
within reach.

---

## D. CODE THAT WILL THROW SOON — 🟠

| Where | Problem | When it crashes |
|---|---|---|
| [products_view.dart:1767](lib/features/products/products_view.dart#L1767) & [1987](lib/features/products/products_view.dart#L1987) | `widget.inventory.first.id` with no empty-check | Adding a recipe line **before any inventory item exists** → `RangeError`. Very likely on a fresh store. |
| [tender_sheet.dart:609](lib/features/tender/tender_sheet.dart#L609) | `method!.title` null-bang | Tapping Back while no tender method selected → null crash. |
| [orders_view.dart:107](lib/features/orders/orders_view.dart#L107) | "Today" filter uses local `DateTime.now()` vs UTC-stored time, no `.toLocal()` | Evening orders (PH is UTC+8) land on the **wrong day** in the list/reports. |
| [dashboard_view.dart:239](lib/features/dashboard/dashboard_view.dart#L239) | `tenant!` null-bang | Frame crash if tenant hydration hasn't finished / session drops. |

(Good news: stock deduction now happens **after** the order RPC succeeds and is
skipped on error — [tender_sheet.dart:788-800](lib/features/tender/tender_sheet.dart#L788) — and async `setState`
calls are guarded with `mounted`. Those earlier worries are clean.)

---

## E. POS FEATURE RESEARCH — standard cafe-POS capabilities vs. this app

| Capability | Status here | Notes |
|---|---|---|
| Ring up items, modifiers, add-ons | ✅ Good | Sizes/temps/strengths + recipe deduction all work |
| Edit cart before pay | ✅ Good | Remove line, change qty, clear |
| Split tender / multiple payment methods | ✅ Good | Cash, GCash, PayMaya, Card, Bank, Other; change tracked |
| **Void after pay** | ❌ Dead button | RPC exists, unwired, no restock |
| **Refund (full + partial)** | ❌ Missing | No method, no RPC |
| **Manager-PIN approval for void/refund** | ❌ Missing | Key anti-theft control |
| **Reason codes** | ⚠️ Partial | Inventory has them but discards; orders have none |
| **X / Z reading** | ❌ Missing | No shift, no cash-up |
| **Cash drawer / shift / float** | ❌ Missing | Can't balance the till |
| **Stock movement ledger** | ❌ Missing | Only a live number, no history |
| **Discounts / comps / price override** | ⚠️ Order-level discount only | No comp/free-staff-drink path, no audit |
| **Open tabs / park & recall order** | ❌ Missing | Can't hold an order to ring another |
| **Kitchen/barista ticket** | ❌ Missing | Printing module exists but tender doesn't print yet |
| **Reprint receipt** | ❌ Dead button | |
| Low-stock alerting at till | ❌ Missing | Only on inventory page |
| COGS / margin reporting | ❌ Missing | Cost captured, never used |

---

## Suggested order of work

**Batch 1 — make the till trustworthy (do first):**
1. Wire **Void** (confirm dialog + reason + **manager PIN**) → call existing
   `voidOrder()`, and **add inventory restock** to the void RPC.
2. Build **Refund** (RPC + restock + reason + manager PIN), full then per-line.
3. Stop centavo loss on price edit ([products_view.dart:1032/1084](lib/features/products/products_view.dart#L1032)).
4. Guard the two `inventory.first` crashes and the `tender_sheet` null-bang.

**Batch 2 — money you can count:**
5. **Shift / cash-drawer** model (open float → close count → over/short).
6. **Z-Reading** (+ X-Reading) built on the shift, with voids/refunds/discounts and
   cash-expected-vs-counted.

**Batch 3 — inventory you can trust:**
7. **Stock-movement ledger** (persist every restock/waste/recount with reason + who).
8. Block delete of an in-use ingredient (or warn + show which products use it).
9. Expand modifiers/add-ons in `canFulfillOne()` so "Large" can't oversell.
10. Recipe validation (qty > 0, unit-family match) + low-stock badge on the till.
