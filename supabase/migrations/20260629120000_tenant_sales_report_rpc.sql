-- Interactive sales report for the web owner portal (/app).
--
-- The static dashboard (admin_tenant_detail) bakes in fixed windows
-- (30-day payment mix, 14-day daily). This RPC powers an *interactive*
-- report that mirrors the POS app's Reports → Sales lens: the caller
-- picks a date range, optionally drills into a single payment method,
-- and the General/Separated split is driven by the same `separate_sales`
-- flag the app uses (per Category or Product Type).
--
-- Authorization matches the other owner-facing RPCs: the tenant owner
-- (tenants.owner_id = auth.uid()) or an app admin. SECURITY DEFINER so
-- it can read across the tenant's rows under RLS.

create or replace function public.tenant_sales_report(
  p_tenant uuid,
  p_from   timestamptz,
  p_to     timestamptz,
  p_method text default null
) returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
as $function$
declare
  v_method text := nullif(p_method, '');
begin
  if not (public.is_admin()
          or exists (select 1 from public.tenants t
                      where t.id = p_tenant and t.owner_id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  return (
    with paid as (
      select o.id, o.total_cents, o.created_at
      from public.orders o
      where o.tenant_id = p_tenant
        and o.status = 'paid'
        and o.created_at >= p_from
        and o.created_at <  p_to
    ),
    -- Orders that belong to one payment method: every payment on the
    -- order is that method (split-payment orders are excluded from a
    -- single-method drill-down, exactly like the app's paidForMethod).
    pay_by_order as (
      select pm.order_id,
             count(*) as n,
             bool_and(pm.method = v_method) as all_match
      from public.payments pm
      where pm.order_id in (select id from paid)
      group by pm.order_id
    ),
    scoped as (
      select p.id, p.total_cents, p.created_at
      from paid p
      where v_method is null
         or exists (select 1 from pay_by_order x
                     where x.order_id = p.id and x.n > 0 and x.all_match)
    ),
    -- Each line tagged separated/general. A line is "separated" when its
    -- product's Category OR Product Type is flagged separate_sales; we
    -- fall back to matching the denormalised category_name when the
    -- product row is gone (deleted/renamed).
    lines as (
      select sc.id                              as order_id,
             coalesce(nullif(ol.category_name, ''), 'Uncategorized') as category_name,
             ol.line_total_cents,
             ol.quantity,
             ol.sellable_name,
             coalesce(c.separate_sales, pt.separate_sales, cc.separate_sales, false) as separated
      from scoped sc
      join public.order_lines ol on ol.order_id = sc.id
      left join public.products pr      on pr.id = ol.sellable_id
      left join public.categories c     on c.id  = pr.category_id
      left join public.product_types pt on pt.id = pr.type_id
      left join public.categories cc    on cc.tenant_id = p_tenant
                                       and cc.name = ol.category_name
    )
    select jsonb_build_object(
      'range', jsonb_build_object('from', p_from, 'to', p_to, 'method', v_method),
      'kpis', (
        select jsonb_build_object(
          'revenue_cents', coalesce(sum(total_cents), 0),
          'orders', count(*),
          'avg_ticket_cents', coalesce(round(avg(total_cents)), 0),
          'last_order_at', max(created_at)
        ) from scoped
      ),
      -- Line-based totals so the General/Separated banners reconcile to
      -- the category rows below them.
      'split', (
        select jsonb_build_object(
          'general_cents',   coalesce(sum(line_total_cents) filter (where not separated), 0),
          'separated_cents', coalesce(sum(line_total_cents) filter (where separated), 0),
          'general_qty',     coalesce(sum(quantity) filter (where not separated), 0),
          'separated_qty',   coalesce(sum(quantity) filter (where separated), 0)
        ) from lines
      ),
      -- Always across the whole range (NOT method-filtered) so the chips
      -- can show every method's total to drill into.
      'payment_mix', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'method', method, 'amount', amt, 'count', c) order by amt desc), '[]'::jsonb)
        from (
          select pm.method, sum(pm.amount_cents) as amt, count(*) as c
          from public.payments pm
          where pm.order_id in (select id from paid)
          group by pm.method
        ) m
      ),
      'by_category', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'category', category_name, 'cents', cents,
                 'qty', qty, 'separated', separated) order by cents desc), '[]'::jsonb)
        from (
          select category_name, separated,
                 sum(line_total_cents) as cents, sum(quantity) as qty
          from lines group by category_name, separated
        ) g
      ),
      'top_sellers', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'name', sellable_name, 'qty', qty, 'revenue', rev) order by qty desc), '[]'::jsonb)
        from (
          select sellable_name, sum(quantity) as qty, sum(line_total_cents) as rev
          from lines group by sellable_name order by sum(quantity) desc limit 12
        ) t
      ),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'd', d, 'rev', rev, 'orders', orders) order by d), '[]'::jsonb)
        from (
          select (created_at at time zone 'Asia/Manila')::date as d,
                 sum(total_cents) as rev, count(*) as orders
          from scoped group by 1
        ) a
      )
    )
  );
end;
$function$;

grant execute on function public.tenant_sales_report(uuid, timestamptz, timestamptz, text) to authenticated;
