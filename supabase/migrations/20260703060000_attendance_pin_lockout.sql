-- Brute-force protection for the public QR time clock: 5 wrong PINs locks
-- that employee's clock-in for 15 minutes (LOCKED:<minutes> error), counter
-- resets on a correct PIN. Columns live on employees; the check runs inside
-- record_attendance_punch before the PIN comparison.
--
-- Full recreated record_attendance_punch body applied live via
-- mcp apply_migration "attendance_pin_lockout" (2026-07-03). Changes vs prior:
--   * employees.attendance_pin_fails / attendance_locked_until columns
--   * lockout check before PIN verify; increment on BAD_PIN; 5 fails → 15 min
--   * reset counter on success
--   * grants re-asserted: anon + authenticated (public QR flow)

alter table public.employees
  add column if not exists attendance_pin_fails int not null default 0,
  add column if not exists attendance_locked_until timestamptz;
