-- Deep-audit fix: settle_orders (Pay Later settlement) was the only money
-- mutation that wrote no audit_log entry. Same signature (uuid[], text) --
-- CREATE OR REPLACE, so no second overload is created (PGRST203-safe).
create or replace function public.settle_orders(p_order_ids uuid[], p_method text)
returns integer
language plpgsql security definer set search_path to 'public'
as $$
declare v_tenant uuid; v_actor text; r record; n int := 0;
begin
  if p_order_ids is null or array_length(p_order_ids, 1) is null then return 0; end if;
  if (select count(distinct tenant_id) from public.orders where id = any(p_order_ids)) <> 1 then
    raise exception 'MIXED_TENANTS';
  end if;
  select distinct tenant_id into v_tenant from public.orders where id = any(p_order_ids);
  if not exists (select 1 from public.tenants where id = v_tenant and owner_id = auth.uid()) then
    raise exception 'Not authorized';
  end if;
  select coalesce(raw_user_meta_data->>'display_name', email) into v_actor
    from auth.users where id = auth.uid();
  for r in
    select id, order_number, total_cents from public.orders
    where id = any(p_order_ids) and tenant_id = v_tenant and status = 'open'
  loop
    if r.total_cents > 0 then
      insert into public.payments (order_id, method, amount_cents)
      values (r.id, coalesce(nullif(p_method, ''), 'cash'), r.total_cents);
    end if;
    update public.orders set status = 'paid', paid_at = now(), updated_at = now()
     where id = r.id;
    insert into public.audit_log (
      tenant_id, actor_id, actor_name, action, entity_type, entity_id, metadata
    ) values (
      v_tenant, auth.uid(), v_actor, 'order.settle', 'order', r.id,
      jsonb_build_object(
        'order_number', r.order_number,
        'total_cents', r.total_cents,
        'method', coalesce(nullif(p_method, ''), 'cash')
      )
    );
    n := n + 1;
  end loop;
  return n;
end;
$$;
