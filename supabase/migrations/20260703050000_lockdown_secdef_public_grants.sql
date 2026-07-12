-- Harden the RPC surface: SECURITY DEFINER functions were granted EXECUTE to
-- PUBLIC (so the anon role could call them). Each self-checks authorization
-- in-DB, but defense-in-depth says don't expose privileged RPCs to anon at all.
--
-- Strip the PUBLIC/anon grant on every SECURITY DEFINER function, then grant
-- back explicitly:
--   * authenticated  — the app + web portal (owner/staff) callers
--   * anon           — only the pre-auth public flows (login email checks,
--                      public /upgrade, public QR /attend)
--   * service_role   — webhook + cron functions
--   * (trigger functions get no execute grant — they run as definer anyway)
do $$
declare
  r record;
  keep_anon text[] := array[
    'email_is_registered','email_is_member','email_is_portal',
    'lookup_store','submit_upgrade_request',
    'attendance_roster','record_attendance_punch'
  ];
  svc_only text[] := array[
    'activate_subscription_by_request','expire_due_subscriptions',
    'pending_clockout_reminders'
  ];
  trig text[] := array['enforce_plan_cap','seed_trial_subscription'];
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
  loop
    execute format('revoke execute on function public.%I(%s) from public;', r.proname, r.args);
    execute format('revoke execute on function public.%I(%s) from anon;', r.proname, r.args);
    if r.proname = any(trig) then
      continue;
    elsif r.proname = any(svc_only) then
      execute format('grant execute on function public.%I(%s) to service_role;', r.proname, r.args);
    else
      execute format('grant execute on function public.%I(%s) to authenticated;', r.proname, r.args);
      if r.proname = any(keep_anon) then
        execute format('grant execute on function public.%I(%s) to anon;', r.proname, r.args);
      end if;
    end if;
  end loop;
end $$;
