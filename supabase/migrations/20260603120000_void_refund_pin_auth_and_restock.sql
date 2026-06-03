-- Void & Refund with owner/manager PIN authorization + inventory restock.
--
-- Closes the "cashier billed it wrong" gap. Adds:
--   1. orders.recipe_deductions — snapshot of the {inventory_item_id,
--      quantity} the sale deducted, so a void/refund puts exactly that back.
--   2. create_paid_order now persists that snapshot (it already received it).
--   3. An 'authorize_refunds' permission on the Owner role + a new system
--      'Manager' role that also holds it (seeded for existing tenants).
--   4. _authorize_refund_pin() — a PIN is valid if it is the owner PIN OR
--      belongs to an employee whose role carries 'authorize_refunds'.
--   5. void_order(uuid,text,text) and refund_order(uuid,text,text) — both
--      verify the authorizer PIN, RESTOCK inventory, and write audit_log.
--
-- The old void_order(uuid,text) overload stays callable for backward-compat;
-- the client now calls the 3-arg version.

-- 1 ── deduction snapshot column ──────────────────────────────────────
alter table public.orders
  add column if not exists recipe_deductions jsonb not null default '[]'::jsonb;

-- 2 ── create_paid_order: persist the deduction snapshot ───────────────
-- Re-defines the 11-arg version from 20260520042523 with one addition:
-- it writes p_recipe_deductions onto the order row so voids/refunds can
-- reverse the exact amounts.
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

  -- Deduct stock (clamped at zero so a buggy expand never goes negative).
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

-- 3 ── permissions: Owner gains authorize_refunds; seed a Manager role ──
update public.employee_roles
  set permissions = permissions || '["authorize_refunds"]'::jsonb,
      updated_at = now()
  where name = 'Owner'
    and not (permissions @> '["authorize_refunds"]'::jsonb);

insert into public.employee_roles
  (tenant_id, name, icon_name, permissions, requires_pin, is_system, sort_order)
select t.id, 'Manager', 'badge_outlined',
  '["dashboard","sell","orders","reports","inventory","products","authorize_refunds"]'::jsonb,
  true, true, 15
from public.tenants t
where not exists (
  select 1 from public.employee_roles r
  where r.tenant_id = t.id and r.name = 'Manager'
);

-- 4 ── authorizer check: owner PIN OR a role with authorize_refunds ─────
-- Callable only by the tenant's authenticated owner account (we check
-- auth.uid()), so this is delegation/accountability rather than a public
-- attack surface. Returns {ok, kind, employee_id?, name}.
create or replace function public._authorize_refund_pin(
  p_tenant_id uuid,
  p_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_owner uuid;
  v_owner_row public.owner_pins%rowtype;
  v_name text;
  v_emp record;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then
    return jsonb_build_object('ok', false);
  end if;

  -- Owner PIN.
  select * into v_owner_row from public.owner_pins where tenant_id = p_tenant_id;
  if found
     and (v_owner_row.locked_until is null or v_owner_row.locked_until <= now())
     and v_owner_row.pin_hash = extensions.crypt(p_pin, v_owner_row.pin_hash) then
    select coalesce(raw_user_meta_data->>'display_name', email) into v_name
      from auth.users where id = auth.uid();
    return jsonb_build_object('ok', true, 'kind', 'owner',
                              'name', coalesce(v_name, 'Owner'));
  end if;

  -- Any employee whose role carries authorize_refunds (e.g. Manager).
  for v_emp in
    select e.id, e.name, cp.pin_hash, cp.locked_until
    from public.employees e
    join public.employee_roles r
      on r.id = e.role_id and r.tenant_id = e.tenant_id
    join public.cashier_pins cp
      on cp.employee_id = e.id and cp.tenant_id = e.tenant_id
    where e.tenant_id = p_tenant_id
      and r.permissions @> '["authorize_refunds"]'::jsonb
  loop
    if v_emp.locked_until is not null and v_emp.locked_until > now() then
      continue;
    end if;
    if v_emp.pin_hash = extensions.crypt(p_pin, v_emp.pin_hash) then
      return jsonb_build_object('ok', true, 'kind', 'manager',
                                'employee_id', v_emp.id, 'name', v_emp.name);
    end if;
  end loop;

  return jsonb_build_object('ok', false);
end;
$$;

revoke execute on function public._authorize_refund_pin(uuid, text) from public;
revoke execute on function public._authorize_refund_pin(uuid, text) from anon;
grant execute on function public._authorize_refund_pin(uuid, text) to authenticated;

-- 5a ── void_order with PIN auth + restock ─────────────────────────────
create or replace function public.void_order(
  p_order_id uuid,
  p_reason text,
  p_authorizer_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_owner uuid;
  v_actor text;
  v_auth jsonb;
  v_ded jsonb;
  v_item uuid;
  v_qty numeric;
begin
  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then raise exception 'Order not found'; end if;

  select owner_id into v_owner from public.tenants where id = v_order.tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if v_order.status in ('voided', 'refunded', 'cancelled') then
    raise exception 'Order already %', v_order.status;
  end if;

  v_auth := public._authorize_refund_pin(v_order.tenant_id, p_authorizer_pin);
  if (v_auth->>'ok')::boolean is not true then
    raise exception 'bad_authorizer_pin';
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email) into v_actor
    from auth.users where id = auth.uid();

  update public.orders
    set status = 'voided', voided_at = now(), voided_by = auth.uid(),
        void_reason = p_reason, updated_at = now()
    where id = p_order_id;

  -- Put the ingredients back.
  if jsonb_typeof(v_order.recipe_deductions) = 'array' then
    for v_ded in select * from jsonb_array_elements(v_order.recipe_deductions) loop
      v_item := nullif(v_ded->>'inventory_item_id', '')::uuid;
      v_qty := coalesce((v_ded->>'quantity')::numeric, 0);
      if v_item is not null and v_qty > 0 then
        update public.inventory_items
          set current_stock = current_stock + v_qty, updated_at = now()
          where id = v_item and tenant_id = v_order.tenant_id;
      end if;
    end loop;
  end if;

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    v_order.tenant_id, auth.uid(), v_actor,
    'order.void', 'order', p_order_id,
    jsonb_build_object(
      'order_number', v_order.order_number,
      'total_cents', v_order.total_cents,
      'reason', p_reason,
      'authorized_by', v_auth->>'name',
      'authorizer_kind', v_auth->>'kind'
    )
  );

  return jsonb_build_object('ok', true, 'authorized_by', v_auth->>'name');
end;
$$;

revoke execute on function public.void_order(uuid, text, text) from public;
revoke execute on function public.void_order(uuid, text, text) from anon;
grant execute on function public.void_order(uuid, text, text) to authenticated;

-- 5b ── refund_order with PIN auth + restock + payment reversal ─────────
create or replace function public.refund_order(
  p_order_id uuid,
  p_reason text,
  p_authorizer_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_owner uuid;
  v_actor text;
  v_auth jsonb;
  v_ded jsonb;
  v_item uuid;
  v_qty numeric;
begin
  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then raise exception 'Order not found'; end if;

  select owner_id into v_owner from public.tenants where id = v_order.tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  if v_order.status in ('voided', 'refunded', 'cancelled') then
    raise exception 'Order already %', v_order.status;
  end if;

  v_auth := public._authorize_refund_pin(v_order.tenant_id, p_authorizer_pin);
  if (v_auth->>'ok')::boolean is not true then
    raise exception 'bad_authorizer_pin';
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email) into v_actor
    from auth.users where id = auth.uid();

  update public.orders
    set status = 'refunded', refunded_at = now(), refunded_by = auth.uid(),
        refund_reason = p_reason, updated_at = now()
    where id = p_order_id;

  update public.payments
    set refunded = true, refunded_at = now(),
        refunded_amount_cents = amount_cents
    where order_id = p_order_id and refunded = false;

  -- Put the ingredients back.
  if jsonb_typeof(v_order.recipe_deductions) = 'array' then
    for v_ded in select * from jsonb_array_elements(v_order.recipe_deductions) loop
      v_item := nullif(v_ded->>'inventory_item_id', '')::uuid;
      v_qty := coalesce((v_ded->>'quantity')::numeric, 0);
      if v_item is not null and v_qty > 0 then
        update public.inventory_items
          set current_stock = current_stock + v_qty, updated_at = now()
          where id = v_item and tenant_id = v_order.tenant_id;
      end if;
    end loop;
  end if;

  insert into public.audit_log (
    tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
  ) values (
    v_order.tenant_id, auth.uid(), v_actor,
    'order.refund', 'order', p_order_id,
    jsonb_build_object(
      'order_number', v_order.order_number,
      'total_cents', v_order.total_cents,
      'reason', p_reason,
      'authorized_by', v_auth->>'name',
      'authorizer_kind', v_auth->>'kind'
    )
  );

  return jsonb_build_object('ok', true, 'authorized_by', v_auth->>'name');
end;
$$;

revoke execute on function public.refund_order(uuid, text, text) from public;
revoke execute on function public.refund_order(uuid, text, text) from anon;
grant execute on function public.refund_order(uuid, text, text) to authenticated;
