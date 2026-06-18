import 'package:uuid/uuid.dart';

import 'employee.dart' show CompensationType, CompensationTypeX, EmploymentType;

const _uuid = Uuid();

/// Per-tenant payroll configuration. Multipliers are applied on top of the
/// employee's base hourly rate (or pro-rated salary). PH defaults baked in
/// to seed new stores; owner can tweak in Maintenance.
///
/// Standard OT (the 1.25× rate) now lives per-employment-type on
/// [EmploymentTemplate.overtimeMultiplier]; the multipliers below are the
/// labor-law-driven ones that don't vary by employment type.
class PayrollRules {
  double regularHoursPerDay;
  /// Max overtime hours that can be claimed in a single day. 0 = no cap.
  double maxOvertimeHoursPerDay;
  double restDayMultiplier;           // 1.30 — work on scheduled rest day
  double regularHolidayMultiplier;    // 2.00 — work on a regular PH holiday
  double specialHolidayMultiplier;    // 1.30 — work on a special non-working day
  double nightDifferentialMultiplier; // 1.10 — work between night-diff hours

  int nightDiffStartMinutes;
  int nightDiffEndMinutes;

  bool deductUndertime;
  int latenessGraceMinutes;
  bool include13thMonth;

  bool deductSSS;
  bool deductPhilHealth;
  bool deductPagIBIG;
  bool withholdBIR;

  PayrollRules({
    this.regularHoursPerDay = 8,
    this.maxOvertimeHoursPerDay = 0,
    this.restDayMultiplier = 1.30,
    this.regularHolidayMultiplier = 2.0,
    this.specialHolidayMultiplier = 1.30,
    this.nightDifferentialMultiplier = 1.10,
    this.nightDiffStartMinutes = 22 * 60,
    this.nightDiffEndMinutes = 6 * 60,
    this.deductUndertime = true,
    this.latenessGraceMinutes = 5,
    this.include13thMonth = true,
    this.deductSSS = true,
    this.deductPhilHealth = true,
    this.deductPagIBIG = true,
    this.withholdBIR = true,
  });

  PayrollRules copy() => PayrollRules(
        regularHoursPerDay: regularHoursPerDay,
        maxOvertimeHoursPerDay: maxOvertimeHoursPerDay,
        restDayMultiplier: restDayMultiplier,
        regularHolidayMultiplier: regularHolidayMultiplier,
        specialHolidayMultiplier: specialHolidayMultiplier,
        nightDifferentialMultiplier: nightDifferentialMultiplier,
        nightDiffStartMinutes: nightDiffStartMinutes,
        nightDiffEndMinutes: nightDiffEndMinutes,
        deductUndertime: deductUndertime,
        latenessGraceMinutes: latenessGraceMinutes,
        include13thMonth: include13thMonth,
        deductSSS: deductSSS,
        deductPhilHealth: deductPhilHealth,
        deductPagIBIG: deductPagIBIG,
        withholdBIR: withholdBIR,
      );

  factory PayrollRules.fromRow(Map<String, dynamic> row) => PayrollRules(
        regularHoursPerDay:
            (row['regular_hours_per_day'] as num?)?.toDouble() ?? 8,
        maxOvertimeHoursPerDay:
            (row['max_overtime_hours_per_day'] as num?)?.toDouble() ?? 0,
        restDayMultiplier:
            (row['rest_day_multiplier'] as num?)?.toDouble() ?? 1.30,
        regularHolidayMultiplier:
            (row['regular_holiday_multiplier'] as num?)?.toDouble() ?? 2.0,
        specialHolidayMultiplier:
            (row['special_holiday_multiplier'] as num?)?.toDouble() ?? 1.30,
        nightDifferentialMultiplier:
            (row['night_diff_multiplier'] as num?)?.toDouble() ?? 1.10,
        nightDiffStartMinutes:
            (row['night_diff_start_minutes'] as int?) ?? 22 * 60,
        nightDiffEndMinutes:
            (row['night_diff_end_minutes'] as int?) ?? 6 * 60,
        deductUndertime: (row['deduct_undertime'] as bool?) ?? true,
        latenessGraceMinutes:
            (row['lateness_grace_minutes'] as int?) ?? 5,
        include13thMonth: (row['include_13th_month'] as bool?) ?? true,
        deductSSS: (row['deduct_sss'] as bool?) ?? true,
        deductPhilHealth: (row['deduct_philhealth'] as bool?) ?? true,
        deductPagIBIG: (row['deduct_pagibig'] as bool?) ?? true,
        withholdBIR: (row['withhold_bir'] as bool?) ?? true,
      );

  Map<String, dynamic> toRow() => {
        'regular_hours_per_day': regularHoursPerDay,
        'max_overtime_hours_per_day': maxOvertimeHoursPerDay,
        'rest_day_multiplier': restDayMultiplier,
        'regular_holiday_multiplier': regularHolidayMultiplier,
        'special_holiday_multiplier': specialHolidayMultiplier,
        'night_diff_multiplier': nightDifferentialMultiplier,
        'night_diff_start_minutes': nightDiffStartMinutes,
        'night_diff_end_minutes': nightDiffEndMinutes,
        'deduct_undertime': deductUndertime,
        'lateness_grace_minutes': latenessGraceMinutes,
        'include_13th_month': include13thMonth,
        'deduct_sss': deductSSS,
        'deduct_philhealth': deductPhilHealth,
        'deduct_pagibig': deductPagIBIG,
        'withhold_bir': withholdBIR,
      };
}

/// A named leave bucket (Service Incentive Leave, Vacation, Sick, etc.).
/// Owners can add/edit/remove these in Maintenance → Payroll → Leave types.
class LeaveType {
  final String id;
  String name;
  String emoji;
  String? iconName;
  /// Days granted per year. 0 = unlimited.
  int annualDays;
  bool paid;
  String notes;
  int sortOrder;
  /// Seeded by the tenant bootstrap (SIL, Vacation, Sick). The Maintenance
  /// UI shows a BUILT-IN badge and locks edit/remove on these.
  final bool isSystem;

  LeaveType({
    String? id,
    required this.name,
    this.emoji = '🌴',
    this.iconName,
    this.annualDays = 5,
    this.paid = true,
    this.notes = '',
    this.sortOrder = 0,
    this.isSystem = false,
  }) : id = id ?? _uuid.v4();

  factory LeaveType.fromRow(Map<String, dynamic> row) => LeaveType(
        id: row['id'] as String,
        name: row['name'] as String,
        emoji: (row['emoji'] as String?) ?? '🌴',
        iconName: row['icon_name'] as String?,
        annualDays: (row['annual_days'] as int?) ?? 5,
        paid: (row['paid'] as bool?) ?? true,
        notes: (row['notes'] as String?) ?? '',
        sortOrder: (row['sort_order'] as int?) ?? 0,
        isSystem: (row['is_system'] as bool?) ?? false,
      );
}

/// Per-employment-type compensation template. The Add Employee modal looks
/// up the template for the chosen employment type and pre-fills the
/// compensation type + rate + standard-OT multiplier. Owner can still edit
/// any field per-employee — the template only provides the defaults.
class EmploymentTemplate {
  final String id;
  final EmploymentType employmentType;
  CompensationType compensationType;
  /// Default rates in pesos. Only the rate matching [compensationType] is
  /// applied to new employees; the others are kept around so toggling the
  /// comp type in the template doesn't lose the previous value.
  double defaultHourlyRate;
  double defaultDailyRate;
  double defaultMonthlySalary;
  /// Standard OT multiplier for this employment type (1.25 typical PH).
  double overtimeMultiplier;
  /// Leave types employees with this employment type can avail.
  Set<String> leaveTypeIds;

  EmploymentTemplate({
    required this.id,
    required this.employmentType,
    this.compensationType = CompensationType.hourly,
    this.defaultHourlyRate = 0,
    this.defaultDailyRate = 0,
    this.defaultMonthlySalary = 0,
    this.overtimeMultiplier = 1.25,
    Set<String>? leaveTypeIds,
  }) : leaveTypeIds = leaveTypeIds ?? <String>{};

  /// The single rate (in pesos) that applies given the current
  /// [compensationType] — convenient for the Add Employee modal which
  /// pre-fills exactly one rate field.
  double get defaultRate => switch (compensationType) {
        CompensationType.hourly => defaultHourlyRate,
        CompensationType.daily => defaultDailyRate,
        CompensationType.salaried => defaultMonthlySalary,
      };

  factory EmploymentTemplate.fromRow(Map<String, dynamic> row) {
    final leavesRaw = row['leave_type_ids'];
    final leaves = <String>{};
    if (leavesRaw is List) {
      for (final v in leavesRaw) {
        leaves.add(v.toString());
      }
    }
    return EmploymentTemplate(
      id: row['id'] as String,
      employmentType: _employmentTypeFromDb(row['employment_type'] as String?),
      compensationType:
          CompensationTypeX.fromDb(row['compensation_type'] as String?),
      defaultHourlyRate:
          ((row['default_hourly_rate_cents'] as int?) ?? 0) / 100,
      defaultDailyRate:
          ((row['default_daily_rate_cents'] as int?) ?? 0) / 100,
      defaultMonthlySalary:
          ((row['default_monthly_salary_cents'] as int?) ?? 0) / 100,
      overtimeMultiplier:
          (row['overtime_multiplier'] as num?)?.toDouble() ?? 1.25,
      leaveTypeIds: leaves,
    );
  }

  Map<String, dynamic> toRow(String tenantId) => {
        'tenant_id': tenantId,
        'employment_type': _employmentTypeDb(employmentType),
        'compensation_type': compensationType.dbValue,
        'default_hourly_rate_cents': (defaultHourlyRate * 100).round(),
        'default_daily_rate_cents': (defaultDailyRate * 100).round(),
        'default_monthly_salary_cents': (defaultMonthlySalary * 100).round(),
        'overtime_multiplier': overtimeMultiplier,
        'leave_type_ids': leaveTypeIds.toList(),
      };
}

String _employmentTypeDb(EmploymentType t) => switch (t) {
      EmploymentType.fullTime => 'full_time',
      EmploymentType.partTime => 'part_time',
      EmploymentType.contract => 'contract',
      EmploymentType.seasonal => 'seasonal',
    };

EmploymentType _employmentTypeFromDb(String? v) => switch (v) {
      'part_time' => EmploymentType.partTime,
      'contract' => EmploymentType.contract,
      'seasonal' => EmploymentType.seasonal,
      _ => EmploymentType.fullTime,
    };
