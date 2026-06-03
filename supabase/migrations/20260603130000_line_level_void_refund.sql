-- Per-line (single item) void & refund.
--
-- Lets a cashier pull ONE wrong item from a paid order instead of reversing
-- the whole ticket. Each reversed line restocks only its own ingredients and
-- the order total is recomputed from the lines that remain. When the last
-- active line is reversed, the whole order flips to voided/refunded.

-- 1 ── per-line status, reversal context, and ingredient snapshot
alter table public.order_lines
  add column if not exists status text not null default 'active'
    check (status in ('active', 'voided', 'refunded')),
  add column if not exists reverse_reason text,
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references auth.users(id) on delete set null,
  add column if not exists recipe_deductions jsonb not null default '[]'::jsonb;

-- 2 ── create_paid_order: store each line's own deductions snapshot
-- Re-defines the 11-arg version, now persisting l.recipe_deductions onto each
-- order_lines row (in addition to the order-level snapshot from migration 1).
create or replace function public.create_paid_order(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_lines jsonb,
  p_payments jsonb,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_notes text default null,
  p_discount_cents int default 0,
  p_employee_id uuid default null,
  p_employee_name text default null,
  p_recipe_deductions jsonb default '[]'::jsonb
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
  v_ded jsonb;
  v_item_id uuid;
  v_qty numeric;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if p_employee_id is not null and not exists (
    select 1 from public.employees
    where id = p_employee_id and tenant_id = p_tenant_id
  ) then
    raise exception 'employee_not_in_tenant';
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email)
    into v_actor
    from auth.users where id = auth.uid();

  insert into public.tenant_order_counters (tenant_id, last_number)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update
    set last_number = tenant_order_counters.last_number + 1,
        updated_at = now()
  returning last_number into v_order_number;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_subtotal := v_subtotal + coalesce((v_line->>'line_total_cents')::int, 0);
  end loop;
  v_total := greatest(v_subtotal - coalesce(p_discount_cents, 0), 0);

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
    paid_at,
    employee_id, employee_name,
    recipe_deductions
  ) values (
    p_tenant_id, p_branch_id, auth.uid(), v_actor, v_order_number, v_status,
    v_subtotal, coalesce(p_discount_cents, 0), v_total,
    p_customer_name, p_customer_phone, p_notes,
    case when v_status = 'paid' then now() else null end,
    p_employee_id, p_employee_name,
    case when jsonb_typeof(p_recipe_deductions) = 'array'
         then p_recipe_deductions else '[]'::jsonb end
  ) returning id into v_order_id;

  insert into public.order_lines (
    order_id, sellable_id, sellable_name, category_name, emoji,
    unit_price_cents, quantity, line_total_cents, modifiers_json,
    recipe_deductions
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
    case when l ? 'modifiers_json' then l->'modifiers_json' else null end,
    case when jsonb_typeof(l->'recipe_deductions') = 'array'
         then l->'recipe_deductions' else '[]'::jsonb end
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

  if jsonb_typeof(p_recipe_deductions) = 'array' then
    for v_ded in select * from jsonb_array_elements(p_recipe_deductions) loop
      v_item_id := nullif(v_ded->>'inventory_item_id', '')::uuid;
      v_qty := coalesce((v_ded->>'quantity')::numeric, 0);
      if v_item_id is not null and v_qty > 0 then
        update public.inventory_items
        set current_stock = greatest(current_stock - v_qty, 0),
            updated_at = now()
        where id = v_item_id and tenant_id = p_tenant_id;
      end if;
    end loop;
  end if;

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    p_tenant_id, auth.uid(), v_actor,
    'order.create', 'order', v_order_id,
    jsonb_build_object(
      'order_number', v_order_number,
      'total_cents', v_total,
      'line_count', jsonb_array_length(p_lines),
      'tender_count', jsonb_array_length(p_payments),
      'employee_id', p_employee_id,
      'employee_name', p_employee_name
    )
  );

  return v_order_id;
end;
$$;

grant execute on function public.create_paid_order(
  uuid, uuid, jsonb, jsonb, text, text, text, int, uuid, text, jsonb
) to authenticated;

-- 3 ── reverse_order_line: void/refund a single line + restock + recompute
create or replace function public.reverse_order_line(
  p_line_id uuid,
  p_kind text,            -- 'void' | 'refund'
  p_reason text,
  p_authorizer_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_line public.order_lines%rowtype;
  v_order public.orders%rowtype;
  v_owner uuid;
  v_actor text;
  v_auth jsonb;
  v_ded jsonb;
  v_item uuid;
  v_qty numeric;
  v_new_status text;
  v_subtotal int;
  v_total int;
  v_active int;
begin
  if p_kind not in ('void', 'refund') then
    raise exception 'bad_kind';
  end if;

  select * into v_line from public.order_lines where id = p_line_id;
  if v_line.id is null then raise exception 'Line not found'; end if;

  select * into v_order from public.orders where id = v_line.order_id;
  if v_order.id is null then raise exception 'Order not found'; end if;

  select owner_id into v_owner from public.tenants where id = v_order.tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if v_order.status in ('voided', 'refunded', 'cancelled') then
    raise exception 'Order already %', v_order.status;
  end if;
  if v_line.status <> 'active' then
    raise exception 'line_already_reversed';
  end if;

  v_auth := public._authorize_refund_pin(v_order.tenant_id, p_authorizer_pin);
  if (v_auth->>'ok')::boolean is not true then
    raise exception 'bad_authorizer_pin';
  end if;

  v_new_status := case when p_kind = 'refund' then 'refunded' else 'voided' end;

  update public.order_lines
    set status = v_new_status, reverse_reason = p_reason,
        reversed_at = now(), reversed_by = auth.uid()
    where id = p_line_id;

  -- Restock just this line's ingredients.
  if jsonb_typeof(v_line.recipe_deductions) = 'array' then
    for v_ded in select * from jsonb_array_elements(v_line.recipe_deductions) loop
      v_item := nullif(v_ded->>'inventory_item_id', '')::uuid;
      v_qty := coalesce((v_ded->>'quantity')::numeric, 0);
      if v_item is not null and v_qty > 0 then
        update public.inventory_items
          set current_stock = current_stock + v_qty, updated_at = now()
          where id = v_item and tenant_id = v_order.tenant_id;
      end if;
    end loop;
  end if;

  -- Recompute order totals from the lines that remain active.
  select coalesce(sum(line_total_cents), 0), count(*)
    into v_subtotal, v_active
    from public.order_lines
    where order_id = v_order.id and status = 'active';
  v_total := greatest(v_subtotal - coalesce(v_order.discount_cents, 0), 0);

  update public.orders
    set subtotal_cents = v_subtotal,
        total_cents = v_total,
        updated_at = now(),
        status = case when v_active = 0 then v_new_status else status end,
        voided_at = case when v_active = 0 and p_kind = 'void' then now() else voided_at end,
        voided_by = case when v_active = 0 and p_kind = 'void' then auth.uid() else voided_by end,
        void_reason = case when v_active = 0 and p_kind = 'void' then p_reason else void_reason end,
        refunded_at = case when v_active = 0 and p_kind = 'refund' then now() else refunded_at end,
        refunded_by = case when v_active = 0 and p_kind = 'refund' then auth.uid() else refunded_by end,
        refund_reason = case when v_active = 0 and p_kind = 'refund' then p_reason else refund_reason end
    where id = v_order.id;

  -- If the whole order is now refunded, flag its payments.
  if v_active = 0 and p_kind = 'refund' then
    update public.payments
      set refunded = true, refunded_at = now(),
          refunded_amount_cents = amount_cents
      where order_id = v_order.id and refunded = false;
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email) into v_actor
    from auth.users where id = auth.uid();

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    v_order.tenant_id, auth.uid(), v_actor,
    case when p_kind = 'refund' then 'order.line_refund' else 'order.line_void' end,
    'order_line', p_line_id,
    jsonb_build_object(
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'line_name', v_line.sellable_name,
      'line_total_cents', v_line.line_total_cents,
      'reason', p_reason,
      'authorized_by', v_auth->>'name',
      'authorizer_kind', v_auth->>'kind',
      'order_status_now', case when v_active = 0 then v_new_status else 'paid' end
    )
  );

  return jsonb_build_object(
    'ok', true,
    'order_status', case when v_active = 0 then v_new_status else 'paid' end,
    'new_total_cents', v_total
  );
end;
$$;

revoke execute on function public.reverse_order_line(uuid, text, text, text) from public;
revoke execute on function public.reverse_order_line(uuid, text, text, text) from anon;
grant execute on function public.reverse_order_line(uuid, text, text, text) to authenticated;
