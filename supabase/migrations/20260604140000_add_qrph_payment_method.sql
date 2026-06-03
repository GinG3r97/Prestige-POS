-- Allow 'qrph' (QR Ph — the interoperable national QR that covers GCash, Maya,
-- and banks) as a payment method alongside the existing tokens.
alter table public.payments
  drop constraint if exists payments_method_check;

alter table public.payments
  add constraint payments_method_check
  check (method in ('cash','gcash','paymaya','card','bank_transfer','qrph','other'));
