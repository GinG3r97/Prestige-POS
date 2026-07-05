-- Café Mobile login shield: before emailing an OTP, the app checks that the
-- store code exists AND the email is actually authorized for that store —
-- the primary owner, a co-owner (tenant_members), or portal-enabled staff
-- (mirrors portal_employee's match: portal_enabled + employees.email).
-- Anonymous-callable (pre-login). Returns null when the pair isn't valid, so
-- it leaks nothing for a non-match. New function — no overload risk.
create or replace function public.mobile_login_check(p_code text, p_email text)
  returns jsonb
  language sql
  stable security definer
  set search_path to 'public'
as $function$
  select jsonb_build_object(
    'tenant_id', t.id,
    'business_name', t.business_name,
    'store_code', t.store_code,
    'role', case
      when lower(ou.email) = lower(btrim(p_email)) then 'owner'
      when exists (
        select 1 from public.tenant_members tm
        where tm.tenant_id = t.id
          and lower(tm.email) = lower(btrim(p_email))
      ) then 'owner'
      else 'employee'
    end
  )
  from public.tenants t
  join auth.users ou on ou.id = t.owner_id
  where upper(t.store_code) = upper(btrim(p_code))
    and (
      lower(ou.email) = lower(btrim(p_email))
      or exists (
        select 1 from public.tenant_members tm
        where tm.tenant_id = t.id
          and lower(tm.email) = lower(btrim(p_email))
      )
      or exists (
        select 1 from public.employees e
        where e.tenant_id = t.id
          and e.portal_enabled = true
          and lower(coalesce(e.email, '')) = lower(btrim(p_email))
      )
    )
  limit 1;
$function$;

revoke execute on function public.mobile_login_check(text, text) from public;
grant execute on function public.mobile_login_check(text, text) to anon, authenticated;
