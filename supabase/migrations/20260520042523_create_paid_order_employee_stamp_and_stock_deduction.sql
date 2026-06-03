-- Extends create_paid_order:
--   • stamps employee_id + employee_name on the order (the cashier who
--     rang it up, distinct from cashier_id which already records the
--     Supabase auth user)
--   • deducts stock atomically from inventory_items using a recipe
--     deduction array the client computes via expandRecipe()
--
-- We replace the function rather than alter — Postgres lets us redefine
-- with a new signature, and the old (8-arg) version stays callable until
-- all clients are upgraded. The new version adds two trailing optional
-- params for backwards compatibility on the call side.

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

  -- If the caller passed an employee_id, it must belong to this tenant.
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
    employee_id, employee_name
  ) values (
    p_tenant_id, p_branch_id, auth.uid(), v_actor, v_order_number, v_status,
    v_subtotal, coalesce(p_discount_cents, 0), v_total,
    p_customer_name, p_customer_phone, p_notes,
    case when v_status = 'paid' then now() else null end,
    p_employee_id, p_employee_name
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

  -- Stock deduction. The client passes an aggregated array of
  -- {inventory_item_id, quantity} entries representing the full recipe
  -- impact of this order (sum of every line × its expanded recipe).
  -- We clamp at zero so a buggy expand never drives stock negative.
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
