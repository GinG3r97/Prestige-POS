-- Senior Citizen / PWD discount: 20% off + VAT exemption, with the buyer's
-- name + ID stored on the order for the BIR-required disclosure. The discount
-- amount itself flows through p_discount_cents (computed client-side); these
-- columns + params record WHO it was for so the invoice can disclose it.
alter table public.orders
  add column if not exists sc_pwd_type text,   -- 'senior' | 'pwd' | null
  add column if not exists sc_pwd_name text,
  add column if not exists sc_pwd_id text;

-- create_paid_order gains p_sc_pwd_type/name/id. See the applied migration in
-- the database for the full SECURITY DEFINER body (recreated to insert the new
-- columns + add sc_pwd_type to the audit metadata).
