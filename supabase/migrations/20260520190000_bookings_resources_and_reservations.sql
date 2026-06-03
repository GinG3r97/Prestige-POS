-- Bookings module — co-working / room reservations.
-- Two tables + RLS + a seed of demo resources per tenant.

create table if not exists public.bookable_resources (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  name            text not null,
  kind            text not null default 'room'
                    check (kind in ('room', 'desk', 'space')),
  capacity        integer not null default 1,
  hourly_rate_cents integer not null default 0,
  color           text,
  icon_name       text,
  sort_order      integer not null default 0,
  is_active       boolean not null default true,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (tenant_id, name)
);
create index if not exists bookable_resources_tenant_idx
  on public.bookable_resources (tenant_id, sort_order);

alter table public.bookable_resources enable row level security;
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname='public' and tablename='bookable_resources'
               and policyname='bookable_resources_owner_all') then
    drop policy bookable_resources_owner_all on public.bookable_resources;
  end if;
end $$;
create policy bookable_resources_owner_all
  on public.bookable_resources for all
  using (tenant_id in (select id from public.tenants where owner_id = auth.uid()))
  with check (tenant_id in (select id from public.tenants where owner_id = auth.uid()));

create or replace function public.touch_bookable_resources_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_touch_resources on public.bookable_resources;
create trigger trg_touch_resources
before update on public.bookable_resources
for each row execute function public.touch_bookable_resources_updated_at();


create table if not exists public.bookings (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  resource_id     uuid not null references public.bookable_resources(id) on delete restrict,
  customer_name   text not null,
  customer_phone  text,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  status          text not null default 'confirmed'
                    check (status in ('confirmed', 'cancelled', 'no_show', 'completed')),
  price_cents     integer not null default 0,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists bookings_resource_time_idx
  on public.bookings (resource_id, starts_at);
create index if not exists bookings_tenant_day_idx
  on public.bookings (tenant_id, starts_at);

alter table public.bookings enable row level security;
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname='public' and tablename='bookings'
               and policyname='bookings_owner_all') then
    drop policy bookings_owner_all on public.bookings;
  end if;
end $$;
create policy bookings_owner_all
  on public.bookings for all
  using (tenant_id in (select id from public.tenants where owner_id = auth.uid()))
  with check (tenant_id in (select id from public.tenants where owner_id = auth.uid()));

create or replace function public.touch_bookings_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_touch_bookings on public.bookings;
create trigger trg_touch_bookings
before update on public.bookings
for each row execute function public.touch_bookings_updated_at();


insert into public.bookable_resources
  (tenant_id, name, kind, capacity, hourly_rate_cents, color, icon_name, sort_order)
select t.id, r.name, r.kind, r.cap, r.rate, r.col, r.icon, r.so
from public.tenants t
cross join (values
    ('Meeting Room A', 'room', 8, 30000, '#B07C4F', 'meeting_room_outlined', 10),
    ('Meeting Room B', 'room', 4, 20000, '#7C8F65', 'meeting_room_outlined', 20),
    ('Hot Desk 1',     'desk', 1, 5000,  '#6E7A8A', 'chair_outlined', 30),
    ('Hot Desk 2',     'desk', 1, 5000,  '#6E7A8A', 'chair_outlined', 40),
    ('Event Space',    'space', 30, 100000, '#A04545', 'celebration_outlined', 50)
) as r(name, kind, cap, rate, col, icon, so)
where not exists (
  select 1 from public.bookable_resources br where br.tenant_id = t.id
);
