import 'package:uuid/uuid.dart';

import 'employee.dart';

const _uuid = Uuid();

/// A logged shift: hours an employee worked on a specific calendar day.
/// One entry per day per employee — the cashier or manager fills the
/// hours field, no clock-in/out punching for v1.
class TimeEntry {
  final String id;
  final String employeeId;
  final DateTime date;
  /// Hours worked on this date. Decimal — 7.5 = 7h30m.
  double hours;
  String notes;

  TimeEntry({
    String? id,
    required this.employeeId,
    required this.date,
    this.hours = 0,
    this.notes = '',
  }) : id = id ?? _uuid.v4();

  factory TimeEntry.fromRow(Map<String, dynamic> row) => TimeEntry(
        id: row['id'] as String,
        employeeId: row['employee_id'] as String,
        date: DateTime.parse(row['entry_date'] as String),
        hours: ((row['hours'] as num?) ?? 0).toDouble(),
        notes: (row['notes'] as String?) ?? '',
      );

  /// Row body for INSERT / UPDATE. `entry_date` is the DATE column.
  /// We strip time so a midnight-UTC drift doesn't push a shift to
  /// the wrong day.
  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'employee_id': employeeId,
        'entry_date': _toDateOnly(date),
        'hours': hours,
        'notes': notes.isEmpty ? null : notes,
      };
}

String _toDateOnly(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// Snapshot of a single employee's payslip for one pay period.
/// Computed when a [PayrollRun] is generated; mutable so a manager can
/// tweak deductions / bonuses before marking paid.
class Payslip {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeRole;
  final CompensationType compensationType;
  /// Hours worked in the period (0 for pure salaried unless tracked).
  double hoursWorked;
  /// Hourly rate at time of run.
  double hourlyRate;
  /// Daily rate at time of run.
  double dailyRate;
  /// Monthly salary at time of run (full month).
  double monthlySalary;
  /// Bonuses / commission to add to gross.
  double bonus;
  /// Deductions (advances, late, missing items, taxes).
  double deductions;

  Payslip({
    String? id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeRole,
    required this.compensationType,
    this.hoursWorked = 0,
    this.hourlyRate = 0,
    this.dailyRate = 0,
    this.monthlySalary = 0,
    this.bonus = 0,
    this.deductions = 0,
  }) : id = id ?? _uuid.v4();

  /// Pesos → whole centavos, rounded to the nearest centavo. ALL pay math runs
  /// in integer centavos so summing many slips can't drift by fractions of a
  /// centavo — floating-point pesos was the bug this avoids.
  static int _toCentavos(double pesos) => (pesos * 100).round();

  /// Gross pay in whole centavos (before deductions). Hourly = hours×rate.
  /// Daily = (hours/8)×rate. Salaried = monthlySalary pro-rated by the period
  /// (weekly = /4.33, biweekly = /2.165). Bonus is added on top.
  int grossCentavosFor(PayPeriodKind period) {
    int base;
    switch (compensationType) {
      case CompensationType.hourly:
        base = _toCentavos(hoursWorked * hourlyRate);
      case CompensationType.daily:
        final daysWorked = hoursWorked / 8.0;
        base = _toCentavos(daysWorked * dailyRate);
      case CompensationType.salaried:
        final divisor = switch (period) {
          PayPeriodKind.weekly => 4.333,
          PayPeriodKind.biweekly => 2.167,
          PayPeriodKind.semiMonthly => 2.0,
          PayPeriodKind.monthly => 1.0,
        };
        base = _toCentavos(monthlySalary / divisor);
    }
    return base + _toCentavos(bonus);
  }

  /// Net pay in whole centavos (gross − deductions).
  int netCentavosFor(PayPeriodKind period) =>
      grossCentavosFor(period) - _toCentavos(deductions);

  /// Gross/net in pesos for display — derived from the centavo math so the
  /// number shown matches the summed run total to the centavo.
  double grossFor(PayPeriodKind period) => grossCentavosFor(period) / 100.0;
  double netFor(PayPeriodKind period) => netCentavosFor(period) / 100.0;

  factory Payslip.fromRow(Map<String, dynamic> row) => Payslip(
        id: row['id'] as String,
        employeeId: (row['employee_id'] as String?) ?? '',
        employeeName: (row['employee_name'] as String?) ?? '',
        employeeRole: (row['employee_role'] as String?) ?? '',
        compensationType: CompensationTypeX.fromDb(
            row['compensation_type'] as String?),
        hoursWorked: ((row['hours_worked'] as num?) ?? 0).toDouble(),
        hourlyRate: ((row['hourly_rate'] as num?) ?? 0).toDouble(),
        dailyRate: ((row['daily_rate'] as num?) ?? 0).toDouble(),
        monthlySalary:
            ((row['monthly_salary'] as num?) ?? 0).toDouble(),
        bonus: ((row['bonus'] as num?) ?? 0).toDouble(),
        deductions: ((row['deductions'] as num?) ?? 0).toDouble(),
      );

  Map<String, dynamic> toRowPayload({
    required String tenantId,
    required String payrollRunId,
  }) =>
      {
        'tenant_id': tenantId,
        'payroll_run_id': payrollRunId,
        'employee_id': employeeId.isEmpty ? null : employeeId,
        'employee_name': employeeName,
        'employee_role': employeeRole,
        'compensation_type': compensationType.dbValue,
        'hours_worked': hoursWorked,
        'hourly_rate': hourlyRate,
        'daily_rate': dailyRate,
        'monthly_salary': monthlySalary,
        'bonus': bonus,
        'deductions': deductions,
      };
}

enum PayPeriodKind { weekly, biweekly, semiMonthly, monthly }

extension PayPeriodKindX on PayPeriodKind {
  String get label => switch (this) {
        PayPeriodKind.weekly => 'Weekly',
        PayPeriodKind.biweekly => 'Bi-weekly',
        PayPeriodKind.semiMonthly => 'Semi-monthly (15th & 30th)',
        PayPeriodKind.monthly => 'Monthly',
      };

  String get dbValue => switch (this) {
        PayPeriodKind.weekly => 'weekly',
        PayPeriodKind.biweekly => 'biweekly',
        PayPeriodKind.semiMonthly => 'semi_monthly',
        PayPeriodKind.monthly => 'monthly',
      };

  static PayPeriodKind fromDb(String? v) => switch (v) {
        'biweekly' => PayPeriodKind.biweekly,
        'semi_monthly' => PayPeriodKind.semiMonthly,
        'monthly' => PayPeriodKind.monthly,
        _ => PayPeriodKind.weekly,
      };
}

enum PayrollStatus { draft, finalized, paid }

extension PayrollStatusX on PayrollStatus {
  String get label => switch (this) {
        PayrollStatus.draft => 'Draft',
        PayrollStatus.finalized => 'Finalized',
        PayrollStatus.paid => 'Paid',
      };

  String get dbValue => switch (this) {
        PayrollStatus.draft => 'draft',
        PayrollStatus.finalized => 'finalized',
        PayrollStatus.paid => 'paid',
      };

  static PayrollStatus fromDb(String? v) => switch (v) {
        'finalized' => PayrollStatus.finalized,
        'paid' => PayrollStatus.paid,
        _ => PayrollStatus.draft,
      };
}

/// A pay period bundle — one row per employee (their [Payslip]). Created on
/// demand by the owner; mutable while draft, locked once paid.
class PayrollRun {
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PayPeriodKind kind;
  PayrollStatus status;
  List<Payslip> slips;
  DateTime createdAt;
  DateTime? paidAt;

  PayrollRun({
    String? id,
    required this.periodStart,
    required this.periodEnd,
    required this.kind,
    this.status = PayrollStatus.draft,
    List<Payslip>? slips,
    DateTime? createdAt,
    this.paidAt,
  })  : id = id ?? _uuid.v4(),
        slips = slips ?? <Payslip>[],
        createdAt = createdAt ?? DateTime.now();

  // Sum in integer centavos, convert to pesos once — no per-slip float drift.
  int get totalGrossCentavos =>
      slips.fold(0, (acc, s) => acc + s.grossCentavosFor(kind));
  int get totalNetCentavos =>
      slips.fold(0, (acc, s) => acc + s.netCentavosFor(kind));
  double get totalGross => totalGrossCentavos / 100.0;
  double get totalNet => totalNetCentavos / 100.0;
  double get totalDeductions =>
      slips.fold(0, (acc, s) => acc + Payslip._toCentavos(s.deductions)) /
          100.0;

  factory PayrollRun.fromRow(
    Map<String, dynamic> row, {
    List<Payslip> slips = const [],
  }) =>
      PayrollRun(
        id: row['id'] as String,
        periodStart: DateTime.parse(row['period_start'] as String),
        periodEnd: DateTime.parse(row['period_end'] as String),
        kind: PayPeriodKindX.fromDb(row['kind'] as String?),
        status: PayrollStatusX.fromDb(row['status'] as String?),
        slips: slips,
        createdAt: row['created_at'] == null
            ? null
            : DateTime.parse(row['created_at'] as String).toLocal(),
        paidAt: row['paid_at'] == null
            ? null
            : DateTime.parse(row['paid_at'] as String).toLocal(),
      );

  /// Row body for INSERT / UPDATE. Slips persist separately in their
  /// own table — see [Payslip.toRowPayload].
  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'period_start': _toDateOnly(periodStart),
        'period_end': _toDateOnly(periodEnd),
        'kind': kind.dbValue,
        'status': status.dbValue,
        'paid_at': paidAt?.toUtc().toIso8601String(),
      };
}
