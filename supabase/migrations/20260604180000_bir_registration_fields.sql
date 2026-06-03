-- BIR (Bureau of Internal Revenue) registration details for compliant Sales
-- Invoices. Per-merchant; printed on every invoice. The vat_registered toggle
-- switches the invoice format (12% VAT breakdown vs a Non-VAT note).
alter table public.tenants
  add column if not exists vat_registered boolean not null default false,
  add column if not exists tin text,
  add column if not exists branch_code text not null default '000',
  add column if not exists bir_min text,            -- Machine Identification Number
  add column if not exists bir_serial text,          -- unit serial number
  add column if not exists ptu_number text,          -- Permit To Use number
  add column if not exists ptu_valid_until text,      -- free-text date (no parsing)
  add column if not exists bir_accreditation_no text; -- supplier accreditation no.
