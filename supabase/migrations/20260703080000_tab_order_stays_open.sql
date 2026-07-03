-- Tabs/pay-later: let create_paid_order force an order to stay 'open' when the
-- caller marks it unpaid, even if the total is 0 (free item) or there are no
-- payments. Without this a ₱0 order is auto-closed as 'paid' and never shows
-- as a customer tab.
--
-- IMPORTANT: this adds a new trailing parameter (p_unpaid). A plain CREATE OR
-- REPLACE would leave the previous 15-arg function in place as a second
-- overload, which makes PostgREST fail to choose a candidate ("PGRST203").
-- So we DROP the old signature first, leaving exactly one function.
drop function if exists public.create_paid_order(
  uuid, uuid, jsonb, jsonb, text, text, text, integer, uuid, text, jsonb, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.create_paid_order(
  p_tenant_id uuid, p_branch_id uuid, p_lines jsonb, p_payments jsonb,
  p_customer_name text DEFAULT NULL::text, p_customer_phone text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text, p_discount_cents integer DEFAULT 0,
  p_employee_id uuid DEFAULT NULL::uuid, p_employee_name text DEFAULT NULL::text,
  p_recipe_deductions jsonb DEFAULT '[]'::jsonb, p_sc_pwd_type text DEFAULT NULL::text,
  p_sc_pwd_name text DEFAULT NULL::text, p_sc_pwd_id text DEFAULT NULL::text,
  p_client_request_id uuid DEFAULT NULL::uuid, p_unpaid boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_owner uuid; v_actor text; v_order_id uuid; v_order_number int;
  v_subtotal int := 0; v_total int := 0; v_paid int := 0;
  v_line jsonb; v_pay jsonb; v_status text; v_ded jsonb;
  v_item_id uuid; v_qty numeric; v_tz text; v_plan text;
  v_limit int; v_plan_limit int; v_override int; v_today int;
  v_sub_status text; v_sub_note text; v_existing uuid;
begin
  select owner_id into v_owner from public.tenants where id = p_tenant_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  -- Idempotency: a retry of the same charge returns the original order.
  if p_client_request_id is not null then
    select id into v_existing from public.orders
      where tenant_id = p_tenant_id and client_request_id = p_client_request_id;
    if v_existing is not null then return v_existing; end if;
  end if;

  select status, nullif(btrim(notes), ''), daily_order_limit_override
    into v_sub_status, v_sub_note, v_override
    from public.tenant_subscriptions where tenant_id = p_tenant_id;
  if v_sub_status in ('paused', 'canceled') then
    raise exception '%', coalesce(v_sub_note,
      'Your Prestige subscription is inactive. Please renew to keep selling. Contact Prestige IT Solutions.');
  end if;

  select coalesce(timezone, 'Asia/Manila') into v_tz from public.tenants where id = p_tenant_id;
  select coalesce(plan, 'trial') into v_plan from public.tenant_subscriptions where tenant_id = p_tenant_id;
  v_plan := coalesce(v_plan, 'trial');
  select daily_order_limit into v_plan_limit from public.plan_limits where plan = v_plan;
  v_limit := coalesce(v_override, v_plan_limit);
  if v_limit is not null then
    select count(*) into v_today from public.orders
      where tenant_id = p_tenant_id
        and (created_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
    if v_today >= v_limit then
      raise exception 'Daily order limit reached — % orders/day on the % plan. It resets at midnight. Upgrade to keep selling.', v_limit, v_plan;
    end if;
  end if;

  if p_employee_id is not null and not exists (
    select 1 from public.employees where id = p_employee_id and tenant_id = p_tenant_id
  ) then
    raise exception 'employee_not_in_tenant';
  end if;

  select coalesce(raw_user_meta_data->>'display_name', email) into v_actor
    from auth.users where id = auth.uid();

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_subtotal := v_subtotal + coalesce((v_line->>'line_total_cents')::int, 0);
  end loop;
  v_total := greatest(v_subtotal - coalesce(p_discount_cents, 0), 0);

  for v_pay in select * from jsonb_array_elements(p_payments) loop
    v_paid := v_paid + coalesce((v_pay->>'amount_cents')::int, 0);
  end loop;
  v_status := case when p_unpaid then 'open'
                   when v_paid >= v_total and v_total > 0 then 'paid'
                   when v_total = 0 then 'paid' else 'open' end;

  insert into public.tenant_order_counters (tenant_id, last_number, grand_total_cents)
  values (p_tenant_id, 1, v_total)
  on conflict (tenant_id) do update
    set last_number = tenant_order_counters.last_number + 1,
        grand_total_cents = tenant_order_counters.grand_total_cents + v_total,
        updated_at = now()
  returning last_number into v_order_number;

  begin
    insert into public.orders (
      tenant_id, branch_id, cashier_id, cashier_name, order_number, status,
      subtotal_cents, discount_cents, total_cents,
      customer_name, customer_phone, notes, paid_at,
      employee_id, employee_name, recipe_deductions,
      sc_pwd_type, sc_pwd_name, sc_pwd_id, client_request_id
    ) values (
      p_tenant_id, p_branch_id, auth.uid(), v_actor, v_order_number, v_status,
      v_subtotal, coalesce(p_discount_cents, 0), v_total,
      p_customer_name, p_customer_phone, p_notes,
      case when v_status = 'paid' then now() else null end,
      p_employee_id, p_employee_name,
      case when jsonb_typeof(p_recipe_deductions) = 'array' then p_recipe_deductions else '[]'::jsonb end,
      p_sc_pwd_type, p_sc_pwd_name, p_sc_pwd_id, p_client_request_id
    ) returning id into v_order_id;
  exception when unique_violation then
    -- concurrent duplicate: return the order the winning call created.
    select id into v_order_id from public.orders
      where tenant_id = p_tenant_id and client_request_id = p_client_request_id;
    return v_order_id;
  end;

  insert into public.order_lines (
    order_id, sellable_id, sellable_name, category_name, emoji,
    unit_price_cents, quantity, line_total_cents, modifiers_json, recipe_deductions
  )
  select v_order_id, nullif(l->>'sellable_id','')::uuid, l->>'sellable_name',
    l->>'category_name', l->>'emoji',
    coalesce((l->>'unit_price_cents')::int,0), coalesce((l->>'quantity')::int,1),
    coalesce((l->>'line_total_cents')::int,0),
    case when l ? 'modifiers_json' then l->'modifiers_json' else null end,
    case when jsonb_typeof(l->'recipe_deductions')='array' then l->'recipe_deductions' else '[]'::jsonb end
  from jsonb_array_elements(p_lines) l;

  insert into public.payments (order_id, method, amount_cents, tendered_cents, change_cents, reference)
  select v_order_id, p->>'method', coalesce((p->>'amount_cents')::int,0),
    nullif(p->>'tendered_cents','')::int, nullif(p->>'change_cents','')::int, nullif(p->>'reference','')
  from jsonb_array_elements(p_payments) p;

  if jsonb_typeof(p_recipe_deductions) = 'array' then
    for v_ded in select * from jsonb_array_elements(p_recipe_deductions) loop
      v_item_id := nullif(v_ded->>'inventory_item_id','')::uuid;
      v_qty := coalesce((v_ded->>'quantity')::numeric, 0);
      if v_item_id is not null and v_qty > 0 then
        update public.inventory_items
          set current_stock = greatest(current_stock - v_qty, 0), updated_at = now()
          where id = v_item_id and tenant_id = p_tenant_id;
      end if;
    end loop;
  end if;

  insert into public.audit_log (tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata)
  values (p_tenant_id, auth.uid(), v_actor, 'order.create', 'order', v_order_id,
    jsonb_build_object('order_number', v_order_number, 'total_cents', v_total,
      'line_count', jsonb_array_length(p_lines), 'tender_count', jsonb_array_length(p_payments),
      'employee_id', p_employee_id, 'employee_name', p_employee_name, 'sc_pwd_type', p_sc_pwd_type));

  return v_order_id;
end;
$function$;

-- Keep the SECURITY DEFINER lockdown posture (see lockdown_secdef_public_grants):
-- recreating the function reset grants to the PUBLIC/anon default.
revoke execute on function public.create_paid_order(
  uuid, uuid, jsonb, jsonb, text, text, text, integer, uuid, text, jsonb, text, text, text, uuid, boolean)
  from public, anon;
