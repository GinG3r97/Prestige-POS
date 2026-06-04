-- Security hardening: remove obsolete function overloads left behind by
-- create-or-replace with changed signatures. The app uses the newest
-- signature of each. Critically, the old 2-arg void_order bypassed the
-- authorizer-PIN gate (it only checked the account owner, which every
-- PIN-signed staff member shares) — a void-without-authorization hole.
drop function if exists public.void_order(uuid, text);
drop function if exists public.create_paid_order(
  uuid, uuid, jsonb, jsonb, text, text, text, integer);
drop function if exists public.verify_owner_pin(uuid, text);
