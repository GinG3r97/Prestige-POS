-- Money layer: orders, order_lines, payments, audit_log, and a per-tenant
-- order-number counter for BIR-compliant sequential numbering.
--
-- Design notes:
--   • Money is stored as integer centavos throughout (no float drift).
--   • Sellable details (name, price, modifiers) are SNAPSHOTTED on each
--     order_line so historical receipts survive product edits/deletes.
--   • order_number is sequential per-tenant; voided orders keep their
--     number so the sequence has no gaps (BIR requirement).
--   • Voids/refunds never delete rows — they update status + write to
--     audit_log so the trail is immutable.

-- ── Per-tenant order counter ──────────────────────────────────────────
-- Gets bumped atomically by the create_paid_order RPC. INSERT...ON CONFLICT
-- gives us thread-safe increment without explicit locking.
create table public.tenant_order_counters (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  last_number int not null default 0,
  updated_at timestamptz not null default now()
);

-- ── orders ────────────────────────────────────────────────────────────
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  cashier_id uuid references auth.users(id) on delete set null,
  cashier_name text,
  -- Sequential per-tenant. BIR-ready.
  order_number int not null,
  status text not null default 'open'
    check (status in ('open','paid','voided','refunded','cancelled')),
  -- All amounts in centavos (₱100 = 10000)
  subtotal_cents int not null default 0,
  discount_cents int not null default 0,
  vat_cents int not null default 0,
  total_cents int not null default 0,
  -- Void / refund / cancel context (filled when status changes)
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  refunded_at timestamptz,
  refunded_by uuid references auth.users(id) on delete set null,
  refund_reason text,
  -- Optional customer info (kept on the order itself for receipt history)
  customer_name text,
  customer_phone text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (tenant_id, order_number)
);

create index orders_tenant_status_idx on public.orders(tenant_id, status);
create index orders_tenant_date_idx on public.orders(tenant_id, created_at desc);
create index orders_branch_idx on public.orders(branch_id);

-- ── order_lines ───────────────────────────────────────────────────────
create table public.order_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  -- Nullable — a sellable can be deleted later; the line keeps its snapshot.
  sellable_id uuid references public.sellables(id) on delete set null,
  -- Snapshot fields. Receipts must still render correctly after edits.
  sellable_name text not null,
  category_name text,
  emoji text,
  unit_price_cents int not null check (unit_price_cents >= 0),
  quantity int not null check (quantity > 0),
  line_total_cents int not null check (line_total_cents >= 0),
  -- Modifier + add-on choices as JSON snapshot (e.g. {"Size": "Large", "Strength": "Strong"})
  modifiers_json jsonb,
  -- True once inventory recipes for this line have been deducted. Used to
  -- prevent double-deduction and to reverse on void/refund.
  recipe_deducted boolean not null default false,
  created_at timestamptz not null default now()
);

create index order_lines_order_idx on public.order_lines(order_id);

-- ── payments ──────────────────────────────────────────────────────────
-- One row per tender. A ₱500 order paid ₱200 cash + ₱300 GCash is two rows.
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  method text not null
    check (method in ('cash','gcash','paymaya','card','bank_transfer','other')),
  amount_cents int not null check (amount_cents > 0),
  -- Cash specifics
  tendered_cents int,
  change_cents int,
  -- Digital specifics (GCash ref, card last 4, bank slip number, etc.)
  reference text,
  -- Refund tracking
  refunded boolean not null default false,
  refunded_at timestamptz,
  refunded_amount_cents int,
  created_at timestamptz not null default now()
);

create index payments_order_idx on public.payments(order_id);

-- ── audit_log ─────────────────────────────────────────────────────────
-- Immutable record of significant state changes (creates, voids, refunds,
-- PIN events, etc.). Insert-only by design — no UPDATE/DELETE policies.
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text,
  action text not null,           -- 'order.create', 'order.void', 'order.refund', etc.
  entity_type text,               -- 'order', 'payment'
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_tenant_date_idx
  on public.audit_log(tenant_id, created_at desc);
create index audit_log_entity_idx
  on public.audit_log(entity_type, entity_id);

-- ── RLS ───────────────────────────────────────────────────────────────
alter table public.tenant_order_counters enable row level security;
alter table public.orders enable row level security;
alter table public.order_lines enable row level security;
alter table public.payments enable row level security;
alter table public.audit_log enable row level security;

create policy "owner reads own order counter"
  on public.tenant_order_counters for select
  using (exists (select 1 from public.tenants t where t.id = tenant_id and t.owner_id = auth.uid()));

-- Note: order counter writes happen exclusively through the SECURITY DEFINER
-- RPC below, so no INSERT/UPDATE policies for direct writes.

create policy "owner reads own orders"
  on public.orders for select
  using (exists (select 1 from public.tenants t where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner updates own orders"
  on public.orders for update
  using (exists (select 1 from public.tenants t where t.id = tenant_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from public.tenants t where t.id = tenant_id and t.owner_id = auth.uid()));

create policy "owner reads own order lines"
  on public.order_lines for select
  using (exists (
    select 1 from public.orders o
    join public.tenants t on t.id = o.tenant_id
    where o.id = order_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own payments"
  on public.payments for select
  using (exists (
    select 1 from public.orders o
    join public.tenants t on t.id = o.tenant_id
    where o.id = order_id and t.owner_id = auth.uid()
  ));

create policy "owner reads own audit log"
  on public.audit_log for select
  using (exists (select 1 from public.tenants t where t.id = tenant_id and t.owner_id = auth.uid()));

-- ── RPC: create_paid_order ────────────────────────────────────────────
-- Atomically: claims next order_number, inserts order + lines + payments,
-- writes audit_log. Returns the new order id. p_lines and p_payments are
-- JSONB arrays. Money everywhere is centavos.
create or replace function public.create_paid_order(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_lines jsonb,
  p_payments jsonb,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_notes text default null,
  p_discount_cents int default 0
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_actor text;
  v_order_id uuid;
  v_order_number int;
  v_subtotal int := 0;
  v_total int := 0;
  v_paid int := 0;
  v_line jsonb;
  v_pay jsonb;
  v_status text;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  -- Resolve actor display name from auth metadata for readable audit + receipts.
  select coalesce(raw_user_meta_data->>'display_name', email)
    into v_actor
    from auth.users where id = auth.uid();

  -- Claim next sequential number atomically.
  insert into public.tenant_order_counters (tenant_id, last_number)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update
    set last_number = tenant_order_counters.last_number + 1,
        updated_at = now()
  returning last_number into v_order_number;

  -- Sum line totals.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_subtotal := v_subtotal + coalesce((v_line->>'line_total_cents')::int, 0);
  end loop;
  v_total := greatest(v_subtotal - coalesce(p_discount_cents, 0), 0);

  -- Sum payment amounts.
  for v_pay in select * from jsonb_array_elements(p_payments) loop
    v_paid := v_paid + coalesce((v_pay->>'amount_cents')::int, 0);
  end loop;

  v_status := case when v_paid >= v_total and v_total > 0 then 'paid'
                   when v_total = 0 then 'paid'
                   else 'open' end;

  insert into public.orders (
    tenant_id, branch_id, cashier_id, cashier_name, order_number, status,
    subtotal_cents, discount_cents, total_cents,
    customer_name, customer_phone, notes,
    paid_at
  ) values (
    p_tenant_id, p_branch_id, auth.uid(), v_actor, v_order_number, v_status,
    v_subtotal, coalesce(p_discount_cents, 0), v_total,
    p_customer_name, p_customer_phone, p_notes,
    case when v_status = 'paid' then now() else null end
  ) returning id into v_order_id;

  insert into public.order_lines (
    order_id, sellable_id, sellable_name, category_name, emoji,
    unit_price_cents, quantity, line_total_cents, modifiers_json
  )
  select
    v_order_id,
    nullif(l->>'sellable_id', '')::uuid,
    l->>'sellable_name',
    l->>'category_name',
    l->>'emoji',
    coalesce((l->>'unit_price_cents')::int, 0),
    coalesce((l->>'quantity')::int, 1),
    coalesce((l->>'line_total_cents')::int, 0),
    case when l ? 'modifiers_json' then l->'modifiers_json' else null end
  from jsonb_array_elements(p_lines) l;

  insert into public.payments (
    order_id, method, amount_cents, tendered_cents, change_cents, reference
  )
  select
    v_order_id,
    p->>'method',
    coalesce((p->>'amount_cents')::int, 0),
    nullif(p->>'tendered_cents', '')::int,
    nullif(p->>'change_cents', '')::int,
    nullif(p->>'reference', '')
  from jsonb_array_elements(p_payments) p;

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    p_tenant_id, auth.uid(), v_actor,
    'order.create', 'order', v_order_id,
    jsonb_build_object(
      'order_number', v_order_number,
      'total_cents', v_total,
      'line_count', jsonb_array_length(p_lines),
      'tender_count', jsonb_array_length(p_payments)
    )
  );

  return v_order_id;
end;
$$;

revoke execute on function public.create_paid_order(uuid, uuid, jsonb, jsonb, text, text, text, int) from public;
revoke execute on function public.create_paid_order(uuid, uuid, jsonb, jsonb, text, text, text, int) from anon;
grant execute on function public.create_paid_order(uuid, uuid, jsonb, jsonb, text, text, text, int) to authenticated;

-- ── RPC: void_order ───────────────────────────────────────────────────
-- Marks the order voided, snapshots reason + actor, writes audit_log.
-- Does NOT delete or alter order_lines/payments — the trail is preserved.
create or replace function public.void_order(
  p_order_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_owner uuid;
  v_actor text;
begin
  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select owner_id into v_owner from public.tenants where id = v_order.tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if v_order.status in ('voided', 'refunded', 'cancelled') then
    raise exception 'Order already %', v_order.status;
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email)
    into v_actor
    from auth.users where id = auth.uid();

  update public.orders
    set status = 'voided',
        voided_at = now(),
        voided_by = auth.uid(),
        void_reason = p_reason,
        updated_at = now()
    where id = p_order_id;

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    v_order.tenant_id, auth.uid(), v_actor,
    'order.void', 'order', p_order_id,
    jsonb_build_object(
      'order_number', v_order.order_number,
      'total_cents', v_order.total_cents,
      'reason', p_reason
    )
  );
end;
$$;

revoke execute on function public.void_order(uuid, text) from public;
revoke execute on function public.void_order(uuid, text) from anon;
grant execute on function public.void_order(uuid, text) to authenticated;