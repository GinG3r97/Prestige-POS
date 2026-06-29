-- Co-owners: let a store have more than one person who can sign into the
-- web owner portal and see sales.
--
-- The schema is single-owner (tenants.owner_id → one auth user). Rather
-- than touch every RLS policy, we add an additive membership table and
-- teach the *owner-portal entry points* to honour it:
--   • my_tenant_id()        — resolves which store the caller manages
--   • admin_tenant_detail() — dashboard payload (SECURITY DEFINER guard)
--   • tenant_sales_report() — interactive sales report (SECURITY DEFINER guard)
--
-- Membership is keyed by EMAIL so a co-owner can be granted before they
-- have ever logged in; their auth user is created on first OTP sign-in and
-- matched by the email claim in their JWT. The original owner_id path is
-- untouched, so existing access is unchanged.

create table if not exists public.tenant_members (
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  email      text not null,
  role       text not null default 'owner',
  created_at timestamptz not null default now(),
  primary key (tenant_id, email)
);

alter table public.tenant_members enable row level security;

-- A signed-in user may read the rows that grant *them* access (handy for a
-- future "stores you can access" UI). All writes go through admin/service.
drop policy if exists tenant_members_self_read on public.tenant_members;
create policy tenant_members_self_read on public.tenant_members
  for select
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

grant select on public.tenant_members to authenticated;

-- True when the current user's email is a member of the given tenant.
create or replace function public.is_tenant_member(p_tenant uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select exists (
    select 1 from public.tenant_members m
    where m.tenant_id = p_tenant
      and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$function$;

grant execute on function public.is_tenant_member(uuid) to authenticated;

-- Resolve the caller's store: the one they own, else one they co-own.
create or replace function public.my_tenant_id()
  returns uuid
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select coalesce(
    (select id from public.tenants where owner_id = auth.uid() limit 1),
    (select m.tenant_id from public.tenant_members m
       where lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
       order by m.created_at
       limit 1)
  );
$function$;

-- Re-point the two owner-facing RPC guards at a shared predicate so owners
-- AND co-owners (and admins) pass.
create or replace function public.admin_tenant_detail(p_tenant uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
as $function$
begin
  if not (public.is_admin()
          or exists (select 1 from public.tenants t where t.id = p_tenant and t.owner_id = auth.uid())
          or public.is_tenant_member(p_tenant)) then
    raise exception 'not authorized';
  end if;
  return (
    select jsonb_build_object(
      'tenant', (select to_jsonb(x) from (select id,business_name,address,currency,timezone,created_at,vat_registered,tin from public.tenants where id=p_tenant) x),
      'subscription', (select to_jsonb(s) from public.tenant_subscriptions s where s.tenant_id=p_tenant),
      'kpis', (
        select jsonb_build_object(
          'revenue_today_cents', coalesce(sum(total_cents) filter (where status='paid' and (created_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date),0),
          'orders_today', count(*) filter (where status='paid' and (created_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date),
          'revenue_7d_cents', coalesce(sum(total_cents) filter (where status='paid' and created_at >= now()-interval '7 days'),0),
          'revenue_30d_cents', coalesce(sum(total_cents) filter (where status='paid' and created_at >= now()-interval '30 days'),0),
          'orders_30d', count(*) filter (where status='paid' and created_at >= now()-interval '30 days'),
          'gross_cents', coalesce(sum(total_cents) filter (where status='paid'),0),
          'orders_total', count(*) filter (where status='paid'),
          'avg_ticket_cents', coalesce(round(avg(total_cents) filter (where status='paid')),0),
          'last_order_at', max(created_at)
        ) from public.orders where tenant_id=p_tenant
      ),
      'daily', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'rev', rev, 'orders', orders) order by d),'[]'::jsonb)
        from (select (created_at at time zone 'Asia/Manila')::date as d, sum(total_cents) as rev, count(*) as orders
          from public.orders where tenant_id=p_tenant and status='paid' and created_at >= now()-interval '14 days' group by 1) a),
      'payment_mix', (select coalesce(jsonb_agg(jsonb_build_object('method', method, 'amount', amt, 'count', c) order by amt desc),'[]'::jsonb)
        from (select pm.method, sum(pm.amount_cents) as amt, count(*) c from public.payments pm join public.orders o on o.id=pm.order_id
          where o.tenant_id=p_tenant and o.status='paid' and pm.created_at >= now()-interval '30 days' group by pm.method) b),
      'top_sellers', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'qty', qty, 'revenue', rev) order by qty desc),'[]'::jsonb)
        from (select ol.sellable_name as name, sum(ol.quantity) qty, sum(ol.line_total_cents) rev from public.order_lines ol join public.orders o on o.id=ol.order_id
          where o.tenant_id=p_tenant and o.status='paid' and o.created_at >= now()-interval '30 days' group by ol.sellable_name order by qty desc limit 8) c),
      'recent_orders', (select coalesce(jsonb_agg(jsonb_build_object('order_number',order_number,'total',total_cents,'status',status,'cashier',cashier_name,'at',created_at) order by created_at desc),'[]'::jsonb)
        from (select * from public.orders where tenant_id=p_tenant order by created_at desc limit 10) d),
      'recent_shifts', (select coalesce(jsonb_agg(jsonb_build_object('status',status,'opened_at',opened_at,'closed_at',closed_at,'opened_by',opened_by_name,'total_sales',total_sales_cents,'orders',order_count,'over_short',over_short_cents) order by opened_at desc),'[]'::jsonb)
        from (select * from public.cashier_shifts where tenant_id=p_tenant order by opened_at desc limit 8) e),
      'counts', jsonb_build_object(
        'products', (select count(*) from public.products where tenant_id=p_tenant),
        'categories', (select count(*) from public.categories where tenant_id=p_tenant),
        'inventory', (select count(*) from public.inventory_items where tenant_id=p_tenant),
        'employees', (select count(*) from public.employees where tenant_id=p_tenant),
        'branches', (select count(*) from public.branches where tenant_id=p_tenant),
        'low_stock', (select count(*) from public.inventory_items where tenant_id=p_tenant and low_stock_threshold is not null and current_stock <= low_stock_threshold)
      ),
      'low_stock_items', (select coalesce(jsonb_agg(jsonb_build_object('name',name,'stock',current_stock,'threshold',low_stock_threshold,'unit',coalesce(unit_label,unit)) order by current_stock),'[]'::jsonb)
        from (select * from public.inventory_items where tenant_id=p_tenant and low_stock_threshold is not null and current_stock <= low_stock_threshold order by current_stock limit 12) f),
      'employees', (select coalesce(jsonb_agg(jsonb_build_object('name',name,'status',status,'role',(select er.name from public.employee_roles er where er.id=e2.role_id))),'[]'::jsonb)
        from (select * from public.employees where tenant_id=p_tenant order by created_at) e2)
    )
  );
end; $function$;

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
          or exists (select 1 from public.tenants t where t.id = p_tenant and t.owner_id = auth.uid())
          or public.is_tenant_member(p_tenant)) then
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
    pay_by_order as (
      select pm.order_id, count(*) as n, bool_and(pm.method = v_method) as all_match
      from public.payments pm
      where pm.order_id in (select id from paid)
      group by pm.order_id
    ),
    scoped as (
      select p.id, p.total_cents, p.created_at
      from paid p
      where v_method is null
         or exists (select 1 from pay_by_order x where x.order_id = p.id and x.n > 0 and x.all_match)
    ),
    lines as (
      select sc.id as order_id,
             coalesce(nullif(ol.category_name, ''), 'Uncategorized') as category_name,
             ol.line_total_cents, ol.quantity, ol.sellable_name,
             coalesce(c.separate_sales, pt.separate_sales, cc.separate_sales, false) as separated
      from scoped sc
      join public.order_lines ol on ol.order_id = sc.id
      left join public.products pr      on pr.id = ol.sellable_id
      left join public.categories c     on c.id  = pr.category_id
      left join public.product_types pt on pt.id = pr.type_id
      left join public.categories cc    on cc.tenant_id = p_tenant and cc.name = ol.category_name
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
      'split', (
        select jsonb_build_object(
          'general_cents',   coalesce(sum(line_total_cents) filter (where not separated), 0),
          'separated_cents', coalesce(sum(line_total_cents) filter (where separated), 0),
          'general_qty',     coalesce(sum(quantity) filter (where not separated), 0),
          'separated_qty',   coalesce(sum(quantity) filter (where separated), 0)
        ) from lines
      ),
      'payment_mix', (
        select coalesce(jsonb_agg(jsonb_build_object('method', method, 'amount', amt, 'count', c) order by amt desc), '[]'::jsonb)
        from (select pm.method, sum(pm.amount_cents) as amt, count(*) as c
              from public.payments pm where pm.order_id in (select id from paid) group by pm.method) m
      ),
      'by_category', (
        select coalesce(jsonb_agg(jsonb_build_object('category', category_name, 'cents', cents, 'qty', qty, 'separated', separated) order by cents desc), '[]'::jsonb)
        from (select category_name, separated, sum(line_total_cents) as cents, sum(quantity) as qty
              from lines group by category_name, separated) g
      ),
      'top_sellers', (
        select coalesce(jsonb_agg(jsonb_build_object('name', sellable_name, 'qty', qty, 'revenue', rev) order by qty desc), '[]'::jsonb)
        from (select sellable_name, sum(quantity) as qty, sum(line_total_cents) as rev
              from lines group by sellable_name order by sum(quantity) desc limit 12) t
      ),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object('d', d, 'rev', rev, 'orders', orders) order by d), '[]'::jsonb)
        from (select (created_at at time zone 'Asia/Manila')::date as d, sum(total_cents) as rev, count(*) as orders
              from scoped group by 1) a
      )
    )
  );
end;
$function$;

-- Grant Karl Didulo co-owner access to Yosef Bookstore Cafe. Resolved by
-- email on his first OTP sign-in at the owner login.
insert into public.tenant_members (tenant_id, email, role)
values ('7b49e801-d5fc-4914-be3f-c8d458be34a8', 'diduloangelou@gmail.com', 'owner')
on conflict (tenant_id, email) do nothing;
