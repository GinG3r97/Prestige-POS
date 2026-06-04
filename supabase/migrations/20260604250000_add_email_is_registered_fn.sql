-- Sign-up shield: lets the client check whether an email already has an
-- account, so onboarding can say "please sign in instead" rather than
-- silently sending an OTP that logs the user into their existing account.
-- SECURITY DEFINER because auth.users is not readable by anon/authenticated.
create or replace function public.email_is_registered(p_email text)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users
    where lower(email) = lower(trim(p_email))
  );
$$;

revoke all on function public.email_is_registered(text) from public;
grant execute on function public.email_is_registered(text) to anon, authenticated;
