-- Per-tenant printer configurations. Owners add their ESC/POS thermal
-- printers in Maintenance → Printers. Each printer has a role
-- (receipt / kitchen / bar) that drives where each kind of print goes,
-- and a transport (lan / bluetooth) describing how to reach it.
create table if not exists public.printer_configs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  name          text not null,
  role          text not null check (role in ('receipt', 'kitchen', 'bar')),
  transport     text not null check (transport in ('lan', 'bluetooth')),
  host          text,
  port          integer default 9100,
  bluetooth_id  text,
  paper_width   integer not null default 58 check (paper_width in (58, 80)),
  auto_print    boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists printer_configs_tenant_idx
  on public.printer_configs (tenant_id, role, sort_order);

alter table public.printer_configs enable row level security;
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname='public' and tablename='printer_configs'
               and policyname='printer_configs_owner_all') then
    drop policy printer_configs_owner_all on public.printer_configs;
  end if;
end $$;
create policy printer_configs_owner_all
  on public.printer_configs for all
  using (tenant_id in (select id from public.tenants where owner_id = auth.uid()))
  with check (tenant_id in (select id from public.tenants where owner_id = auth.uid()));

create or replace function public.touch_printer_configs_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_touch_printer_configs on public.printer_configs;
create trigger trg_touch_printer_configs
before update on public.printer_configs
for each row execute function public.touch_printer_configs_updated_at();
