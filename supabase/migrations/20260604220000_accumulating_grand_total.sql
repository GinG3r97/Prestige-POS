-- Phase 2: non-resettable Accumulated Grand Total (AGT) + Z-counter for
-- BIR-compliant Z-readings, plus per-shift grand-total snapshots.
alter table public.tenant_order_counters
  add column if not exists grand_total_cents bigint not null default 0,
  add column if not exists z_counter int not null default 0;

alter table public.cashier_shifts
  add column if not exists beginning_gt_cents bigint,
  add column if not exists ending_gt_cents bigint,
  add column if not exists z_counter int;

-- create_paid_order is recreated (see the applied migration in the database)
-- to compute the order total BEFORE the counter upsert and add it to the
-- non-resettable grand_total_cents in the same upsert.
