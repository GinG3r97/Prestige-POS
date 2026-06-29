-- The web owner login only emails an OTP to addresses that already exist
-- (admins self-provision; everyone else must already be an owner). Co-owners
-- granted via tenant_members have no auth user yet, so they were rejected
-- with "No account found". This predicate lets the login allow a co-owner
-- email to self-provision on first sign-in. Callable pre-auth (anon).

create or replace function public.email_is_member(p_email text)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select exists (
    select 1 from public.tenant_members
    where lower(email) = lower(trim(p_email))
  );
$function$;

grant execute on function public.email_is_member(text) to anon, authenticated;
