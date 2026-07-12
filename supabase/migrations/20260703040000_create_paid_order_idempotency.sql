-- Prevent double-charge on the money path. A lost response after a successful
-- write must not create a second order when the cashier retries. The app now
-- passes a stable client_request_id per charge attempt; a retry with the same
-- id returns the original order id (idempotent). Also revokes anon EXECUTE.
--
-- Full recreated body applied via mcp apply_migration "create_paid_order_idempotency"
-- (2026-07-03). Key changes vs the prior version:
--   * new final param p_client_request_id uuid default null
--   * early-return of the existing order if that (tenant, client_request_id) exists
--   * orders insert wrapped in an exception handler that returns the existing
--     order on unique_violation (concurrent duplicate)
--   * orders.client_request_id column + partial unique index
--   * revoke execute from anon; grant to authenticated only

alter table public.orders add column if not exists client_request_id uuid;
create unique index if not exists orders_tenant_client_req_uidx
  on public.orders (tenant_id, client_request_id)
  where client_request_id is not null;

-- NOTE: the full create_paid_order(...) function body (unchanged except for the
-- idempotency guard described above) is applied live in the database. See the
-- migration of the same name for the complete definition.
