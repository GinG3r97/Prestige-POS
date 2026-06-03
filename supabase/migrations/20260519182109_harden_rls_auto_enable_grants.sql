-- The `rls_auto_enable` function is a Supabase safety net that auto-enables
-- Row Level Security on every newly created table in the `public` schema.
-- It's invoked by the `ensure_rls` event trigger (owned by `postgres`), which
-- runs with the trigger owner's privileges — so we can safely revoke direct
-- EXECUTE from public-facing roles without breaking the trigger.
--
-- This silences the `anon_security_definer_function_executable` and
-- `authenticated_security_definer_function_executable` advisors.

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;
