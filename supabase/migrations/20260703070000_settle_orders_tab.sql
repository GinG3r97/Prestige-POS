-- Tabs / pay-later: settle a customer's open orders. Marks each given open
-- order paid with a payment equal to its total (chosen method), stamps
-- paid_at. Owner-authorized; all orders must be one owned tenant + 'open'.
-- Unpaid tab orders are created by create_paid_order with an empty payments
-- array (status 'open').
create or replace function public.settle_orders(p_order_ids uuid[], p_method text)
  returns integer
  language plpgsql security definer set search_path to 'public'
as $function$
declare v_tenant uuid; r record; n int := 0;
begin
  if p_order_ids is null or array_length(p_order_ids, 1) is null then return 0; end if;
  if (select count(distinct tenant_id) from public.orders where id = any(p_order_ids)) <> 1 then
    raise exception 'MIXED_TENANTS';
  end if;
  select distinct tenant_id into v_tenant from public.orders where id = any(p_order_ids);
  if not exists (select 1 from public.tenants where id = v_tenant and owner_id = auth.uid()) then
    raise exception 'Not authorized';
  end if;
  for r in
    select id, total_cents from public.orders
    where id = any(p_order_ids) and tenant_id = v_tenant and status = 'open'
  loop
    insert into public.payments (order_id, method, amount_cents)
    values (r.id, coalesce(nullif(p_method, ''), 'cash'), r.total_cents);
    update public.orders set status = 'paid', paid_at = now(), updated_at = now()
     where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$function$;
revoke execute on function public.settle_orders(uuid[], text) from public, anon;
grant execute on function public.settle_orders(uuid[], text) to authenticated;
