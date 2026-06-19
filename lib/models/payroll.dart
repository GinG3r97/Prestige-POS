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
  /// "Other" deductions for THIS period (advances, late, missing items) —
  /// taken as-is, not pro-rated. Statutory items are itemized below.
  double deductions;

  // ── Itemized statutory deductions (employee share, MONTHLY pesos) ──
  // Snapshotted from the employee at run time; pro-rated by pay frequency in
  // [statutoryCentavosFor]. 0 when the tenant has that contribution switched off.
  double sss;
  double philHealth;
  double pagIbig;
  /// Standard hours in a working day — sourced from the tenant's Payroll rules
  /// (Maintenance → Payroll → "Regular hours / day"). Daily-rate pay divides
  /// hours worked by this to get days. Defaults to 8 if unset.
  double regularHoursPerDay;

  // ── Itemized OT / undertime, pulled from attendance (payroll_dtr_period) ──
  /// Approved + capped overtime hours for the period (paid at [otMultiplier]).
  double otHours;
  /// Undertime hours for the period (left early / fell short of schedule).
  double undertimeHours;
  /// Total lateness minutes (already reflected in the credited regular hours;
  /// shown on the DTR for transparency, not deducted twice).
  int lateMinutes;
  /// OT rate multiplier snapshot (employment-type template, default 1.25).
  double otMultiplier;
  /// Whether undertime is deducted from pay (Maintenance → Payroll toggle),
  /// snapshotted so a finalized slip is stable if the rule later changes.
  bool deductUndertime;

  // ── Premiums (paid on top of base) + salaried absences ──
  /// Hours worked on a scheduled day off, paid at [restdayMultiplier].
  double restdayHours;
  double restdayMultiplier;
  /// Night-differential hours, paid the extra at [nightdiffMultiplier].
  double nightdiffHours;
  double nightdiffMultiplier;
  /// Unexcused absent scheduled days — docks SALARIED pay (hourly/daily already
  /// lose the hours).
  int absentDays;

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
    this.sss = 0,
    this.philHealth = 0,
    this.pagIbig = 0,
    this.regularHoursPerDay = 8,
    this.otHours = 0,
    this.undertimeHours = 0,
    this.lateMinutes = 0,
    this.otMultiplier = 1.25,
    this.deductUndertime = true,
    this.restdayHours = 0,
    this.restdayMultiplier = 1.30,
    this.nightdiffHours = 0,
    this.nightdiffMultiplier = 1.10,
    this.absentDays = 0,
  }) : id = id ?? _uuid.v4();

  /// Copy with selected overrides — used when editing bonus/deductions so no
  /// snapshot field is ever accidentally dropped.
  Payslip copyWith({double? bonus, double? deductions}) => Payslip(
        id: id,
        employeeId: employeeId,
        employeeName: employeeName,
        employeeRole: employeeRole,
        compensationType: compensationType,
        hoursWorked: hoursWorked,
        hourlyRate: hourlyRate,
        dailyRate: dailyRate,
        monthlySalary: monthlySalary,
        bonus: bonus ?? this.bonus,
        deductions: deductions ?? this.deductions,
        sss: sss,
        philHealth: philHealth,
        pagIbig: pagIbig,
        regularHoursPerDay: regularHoursPerDay,
        otHours: otHours,
        undertimeHours: undertimeHours,
        lateMinutes: lateMinutes,
        otMultiplier: otMultiplier,
        deductUndertime: deductUndertime,
        restdayHours: restdayHours,
        restdayMultiplier: restdayMultiplier,
        nightdiffHours: nightdiffHours,
        nightdiffMultiplier: nightdiffMultiplier,
        absentDays: absentDays,
      );

  /// Pesos → whole centavos, rounded to the nearest centavo. ALL pay math runs
  /// in integer centavos so summing many slips can't drift by fractions of a
  /// centavo — floating-point pesos was the bug this avoids.
  static int _toCentavos(double pesos) => (pesos * 100).round();

  /// Gross pay in whole centavos (before deductions). Hourly = hours×rate.
  /// Daily = (hours/8)×rate. Salaried = monthlySalary pro-rated by the period
  /// (weekly = /4.33, biweekly = /2.165). Bonus is added on top.
  /// How many of this period fit in a month — used to pro-rate a monthly
  /// salary and the monthly statutory contributions to one pay run.
  static double periodsPerMonth(PayPeriodKind period) => switch (period) {
        PayPeriodKind.weekly => 4.333,
        PayPeriodKind.biweekly => 2.167,
        PayPeriodKind.semiMonthly => 2.0,
        PayPeriodKind.monthly => 1.0,
      };

  int grossCentavosFor(PayPeriodKind period) {
    int base;
    switch (compensationType) {
      case CompensationType.hourly:
        base = _toCentavos(hoursWorked * hourlyRate);
      case CompensationType.daily:
        // Days worked = hours ÷ the configured standard day (Maintenance →
        // Payroll). Guard against a 0/blank setting falling back to 8.
        final perDay = regularHoursPerDay > 0 ? regularHoursPerDay : 8.0;
        final daysWorked = hoursWorked / perDay;
        base = _toCentavos(daysWorked * dailyRate);
      case CompensationType.salaried:
        base = _toCentavos(monthlySalary / periodsPerMonth(period));
    }
    return base +
        otPayCentavos +
        restdayPremiumCentavos +
        nightdiffPremiumCentavos +
        _toCentavos(bonus);
  }

  /// Extra pay for rest-day work (the portion above base — base hours are
  /// already in the regular total).
  int get restdayPremiumCentavos => restdayMultiplier <= 1
      ? 0
      : _toCentavos(restdayHours * hourlyEquivalent * (restdayMultiplier - 1));

  /// Night-differential premium (the extra above base for night hours).
  int get nightdiffPremiumCentavos => nightdiffMultiplier <= 1
      ? 0
      : _toCentavos(
          nightdiffHours * hourlyEquivalent * (nightdiffMultiplier - 1));

  /// Salaried absence deduction — full unexcused days dock the daily-equivalent
  /// (monthly ÷ 26). Hourly/daily already lose the hours, so 0 for them.
  int get absenceDeductionCentavos =>
      compensationType == CompensationType.salaried && absentDays > 0
          ? _toCentavos(absentDays * monthlySalary / 26.0)
          : 0;

  /// Per-hour rate used for OT pay and undertime deductions. Hourly staff use
  /// their hourly rate directly; daily/salaried derive an hourly-equivalent
  /// (daily ÷ hours-per-day; monthly ÷ 26 working days ÷ hours-per-day).
  double get hourlyEquivalent {
    final perDay = regularHoursPerDay > 0 ? regularHoursPerDay : 8.0;
    return switch (compensationType) {
      CompensationType.hourly => hourlyRate,
      CompensationType.daily => dailyRate / perDay,
      CompensationType.salaried => monthlySalary / 26.0 / perDay,
    };
  }

  /// Overtime pay for the period, in centavos (hours × hourly-equiv × multiplier).
  int get otPayCentavos =>
      _toCentavos(otHours * hourlyEquivalent * otMultiplier);

  /// Undertime deduction, in centavos. 0 when the tenant has undertime
  /// deduction switched off (snapshotted in [deductUndertime]).
  int get undertimeCentavos =>
      deductUndertime ? _toCentavos(undertimeHours * hourlyEquivalent) : 0;

  /// Each itemized statutory deduction (SSS / PhilHealth / Pag-IBIG), in
  /// centavos, pro-rated to THIS pay run from the stored monthly amount.
  int sssCentavosFor(PayPeriodKind period) =>
      _toCentavos(sss / periodsPerMonth(period));
  int philHealthCentavosFor(PayPeriodKind period) =>
      _toCentavos(philHealth / periodsPerMonth(period));
  int pagIbigCentavosFor(PayPeriodKind period) =>
      _toCentavos(pagIbig / periodsPerMonth(period));

  /// All statutory deductions combined for the period, in centavos.
  int statutoryCentavosFor(PayPeriodKind period) =>
      sssCentavosFor(period) +
      philHealthCentavosFor(period) +
      pagIbigCentavosFor(period);

  /// Net pay in whole centavos: gross (incl. OT) − statutory (pro-rated) −
  /// undertime − other. Floored at 0 — you can't take home (or withhold more
  /// than) a negative amount; any uncollectible statutory just isn't collected
  /// this run rather than showing a negative payslip.
  int netCentavosFor(PayPeriodKind period) {
    final n = grossCentavosFor(period) -
        statutoryCentavosFor(period) -
        undertimeCentavos -
        absenceDeductionCentavos -
        _toCentavos(deductions);
    return n < 0 ? 0 : n;
  }

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
        sss: ((row['sss'] as num?) ?? 0).toDouble(),
        philHealth: ((row['philhealth'] as num?) ?? 0).toDouble(),
        pagIbig: ((row['pagibig'] as num?) ?? 0).toDouble(),
        otHours: ((row['ot_hours'] as num?) ?? 0).toDouble(),
        undertimeHours: ((row['undertime_hours'] as num?) ?? 0).toDouble(),
        lateMinutes: ((row['late_minutes'] as num?) ?? 0).toInt(),
        otMultiplier: ((row['ot_multiplier'] as num?) ?? 1.25).toDouble(),
        deductUndertime: (row['deduct_undertime'] as bool?) ?? true,
        restdayHours: ((row['restday_hours'] as num?) ?? 0).toDouble(),
        restdayMultiplier:
            ((row['restday_mult'] as num?) ?? 1.30).toDouble(),
        nightdiffHours: ((row['nightdiff_hours'] as num?) ?? 0).toDouble(),
        nightdiffMultiplier:
            ((row['nightdiff_mult'] as num?) ?? 1.10).toDouble(),
        absentDays: ((row['absent_days'] as num?) ?? 0).toInt(),
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
        'sss': sss,
        'philhealth': philHealth,
        'pagibig': pagIbig,
        'ot_hours': otHours,
        'undertime_hours': undertimeHours,
        'late_minutes': lateMinutes,
        'ot_multiplier': otMultiplier,
        'deduct_undertime': deductUndertime,
        'restday_hours': restdayHours,
        'restday_mult': restdayMultiplier,
        'nightdiff_hours': nightdiffHours,
        'nightdiff_mult': nightdiffMultiplier,
        'absent_days': absentDays,
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
  /// Everything withheld between gross and net — statutory + undertime + other.
  double get totalDeductions =>
      (totalGrossCentavos - totalNetCentavos) / 100.0;

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
