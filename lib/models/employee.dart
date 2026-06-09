import 'package:flutter/material.dart' show IconData, Icons;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum EmploymentType { fullTime, partTime, contract, seasonal }

extension EmploymentTypeX on EmploymentType {
  String get label => switch (this) {
        EmploymentType.fullTime => 'Full-time',
        EmploymentType.partTime => 'Part-time',
        EmploymentType.contract => 'Contract',
        EmploymentType.seasonal => 'Seasonal',
      };

  /// Canonical SQL value (matches the CHECK constraint on employees.employment_type).
  String get dbValue => switch (this) {
        EmploymentType.fullTime => 'full_time',
        EmploymentType.partTime => 'part_time',
        EmploymentType.contract => 'contract',
        EmploymentType.seasonal => 'seasonal',
      };

  static EmploymentType fromDb(String? v) => switch (v) {
        'part_time' => EmploymentType.partTime,
        'contract' => EmploymentType.contract,
        'seasonal' => EmploymentType.seasonal,
        _ => EmploymentType.fullTime,
      };
}

/// How an employee is paid.
///  * hourly   — tracked hours × [Employee.hourlyRate]
///  * daily    — days worked × [Employee.dailyRate]
///  * salaried — fixed [Employee.monthlySalary] regardless of hours/days
enum CompensationType { hourly, daily, salaried }

extension CompensationTypeX on CompensationType {
  String get label => switch (this) {
        CompensationType.hourly => 'Hourly',
        CompensationType.daily => 'Daily',
        CompensationType.salaried => 'Salaried',
      };

  String get dbValue => switch (this) {
        CompensationType.hourly => 'hourly',
        CompensationType.daily => 'daily',
        CompensationType.salaried => 'salaried',
      };

  /// Suffix shown next to a money amount in this comp mode.
  String get rateSuffix => switch (this) {
        CompensationType.hourly => '/hr',
        CompensationType.daily => '/day',
        CompensationType.salaried => '/mo',
      };

  static CompensationType fromDb(String? v) => switch (v) {
        'daily' => CompensationType.daily,
        'salaried' => CompensationType.salaried,
        _ => CompensationType.hourly,
      };
}

enum EmployeeStatus { active, onLeave, terminated }

extension EmployeeStatusX on EmployeeStatus {
  String get label => switch (this) {
        EmployeeStatus.active => 'Active',
        EmployeeStatus.onLeave => 'On Leave',
        EmployeeStatus.terminated => 'Terminated',
      };

  String get dbValue => switch (this) {
        EmployeeStatus.active => 'active',
        EmployeeStatus.onLeave => 'on_leave',
        EmployeeStatus.terminated => 'terminated',
      };

  static EmployeeStatus fromDb(String? v) => switch (v) {
        'on_leave' => EmployeeStatus.onLeave,
        'terminated' => EmployeeStatus.terminated,
        _ => EmployeeStatus.active,
      };
}

/// Gender drives the avatar icon shown across the app. Two values today
/// (male/female) — extend here if more are ever needed.
enum Gender { male, female }

extension GenderX on Gender {
  String get label => switch (this) {
        Gender.male => 'Male',
        Gender.female => 'Female',
      };

  String get dbValue => switch (this) {
        Gender.male => 'male',
        Gender.female => 'female',
      };

  IconData get icon => switch (this) {
        Gender.male => Icons.man_outlined,
        Gender.female => Icons.woman_outlined,
      };

  static Gender fromDb(String? v) =>
      v == 'female' ? Gender.female : Gender.male;
}

enum DocumentStatus { approved, pending, expiringSoon, missing }

extension DocumentStatusX on DocumentStatus {
  String get label => switch (this) {
        DocumentStatus.approved => 'Approved',
        DocumentStatus.pending => 'Pending',
        DocumentStatus.expiringSoon => 'Expiring soon',
        DocumentStatus.missing => 'Missing',
      };

  String get dbValue => switch (this) {
        DocumentStatus.approved => 'approved',
        DocumentStatus.pending => 'pending',
        DocumentStatus.expiringSoon => 'expiring_soon',
        DocumentStatus.missing => 'missing',
      };

  static DocumentStatus fromDb(String? v) => switch (v) {
        'approved' => DocumentStatus.approved,
        'expiring_soon' => DocumentStatus.expiringSoon,
        'missing' => DocumentStatus.missing,
        _ => DocumentStatus.pending,
      };
}

class EmployeeDocument {
  final String id;
  String name;
  DocumentStatus status;
  DateTime? expiresOn;

  EmployeeDocument({
    String? id,
    required this.name,
    this.status = DocumentStatus.pending,
    this.expiresOn,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.dbValue,
        'expires_on': expiresOn?.toIso8601String(),
      };

  factory EmployeeDocument.fromJson(Map<String, dynamic> j) => EmployeeDocument(
        id: j['id'] as String?,
        name: (j['name'] as String?) ?? '',
        status: DocumentStatusX.fromDb(j['status'] as String?),
        expiresOn: (j['expires_on'] as String?) != null
            ? DateTime.tryParse(j['expires_on'] as String)
            : null,
      );
}

class WorkShift {
  /// 1 = Monday, 7 = Sunday
  final int weekday;
  String start; // "HH:mm"
  String end; // "HH:mm"

  WorkShift({required this.weekday, required this.start, required this.end});

  Map<String, dynamic> toJson() =>
      {'weekday': weekday, 'start': start, 'end': end};

  factory WorkShift.fromJson(Map<String, dynamic> j) => WorkShift(
        weekday: (j['weekday'] as int?) ?? 1,
        start: (j['start'] as String?) ?? '09:00',
        end: (j['end'] as String?) ?? '17:00',
      );
}

/// A tenant-owned role with a Material icon, route permissions, and a flag
/// for whether holders need a cashier PIN. Seeded with Owner / Cashier /
/// Inventory Manager; owners can add more from Maintenance → Roles.
class EmployeeRole {
  final String id;
  String name;
  String? iconName;
  /// Route keys this role can access. Matches the Dart AppRoute enum names
  /// (e.g. 'sell', 'orders', 'inventory'). Empty set = no access.
  Set<String> permissions;
  bool requiresPin;
  /// System roles are seeded by the tenant bootstrap. They can be renamed
  /// and their permissions edited, but they can't be deleted from the UI
  /// (we keep the safety net so the owner can't lock themselves out).
  final bool isSystem;
  int sortOrder;

  EmployeeRole({
    required this.id,
    required this.name,
    this.iconName,
    Set<String>? permissions,
    this.requiresPin = false,
    this.isSystem = false,
    this.sortOrder = 0,
  }) : permissions = permissions ?? <String>{};

  factory EmployeeRole.fromRow(Map<String, dynamic> row) {
    final raw = row['permissions'];
    final perms = <String>{};
    if (raw is List) {
      for (final p in raw) {
        if (p is String) perms.add(p);
      }
    }
    return EmployeeRole(
      id: row['id'] as String,
      name: row['name'] as String,
      iconName: row['icon_name'] as String?,
      permissions: perms,
      requiresPin: (row['requires_pin'] as bool?) ?? false,
      isSystem: (row['is_system'] as bool?) ?? false,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }

  bool can(String routeKey) => permissions.contains(routeKey);
}

class Employee {
  final String id;
  String name;
  Gender gender;

  /// FK to `employee_roles.id`. Null only during in-progress form state;
  /// every persisted employee has a role.
  String? roleId;

  /// Denormalized role name kept in sync from the joined role row — used
  /// across list/filter/sort UIs that need the human-readable role. The
  /// canonical relation is [roleId]; this field is read-only display state.
  String role;

  // Contact
  String email;
  String phone;

  // Employment
  DateTime hireDate;
  EmployeeStatus status;
  EmploymentType employmentType;
  CompensationType compensationType;
  /// Per-hour rate in pesos. Used when [compensationType] is hourly.
  double hourlyRate;
  /// Per-day rate in pesos. Used when [compensationType] is daily.
  double dailyRate;
  /// Fixed monthly pay in pesos. Used when [compensationType] is salaried.
  double monthlySalary;
  Set<String> branchIds;

  // Schedule (per-weekday shifts; 1=Mon … 7=Sun)
  List<WorkShift> schedule;

  // Requirements / documents
  List<EmployeeDocument> documents;

  // Portal access (employee-facing self-serve portal) — locked in the UI
  // for now, but the field shape stays here so the future feature has a
  // home without further model churn.
  bool portalEnabled;
  String portalGmail;
  String portalUsername;
  DateTime? portalInvitedAt;
  DateTime? portalLastLoginAt;

  String notes;

  /// Plaintext cashier PIN (owner-visible). Empty when none / not loaded.
  String cashierPin;

  Employee({
    String? id,
    required this.name,
    this.gender = Gender.male,
    this.roleId,
    this.role = '',
    this.email = '',
    this.phone = '',
    DateTime? hireDate,
    this.status = EmployeeStatus.active,
    this.employmentType = EmploymentType.fullTime,
    this.compensationType = CompensationType.hourly,
    this.hourlyRate = 0,
    this.dailyRate = 0,
    this.monthlySalary = 0,
    Set<String>? branchIds,
    List<WorkShift>? schedule,
    List<EmployeeDocument>? documents,
    this.portalEnabled = false,
    this.portalGmail = '',
    this.portalUsername = '',
    this.portalInvitedAt,
    this.portalLastLoginAt,
    this.notes = '',
    this.cashierPin = '',
  })  : id = id ?? _uuid.v4(),
        hireDate = hireDate ?? DateTime.now(),
        branchIds = branchIds ?? <String>{},
        schedule = schedule ?? <WorkShift>[],
        documents = documents ?? <EmployeeDocument>[];

  /// Hydrates from a `public.employees` row. The caller passes the joined
  /// role row separately so we can populate both [roleId] and the
  /// denormalized [role] name in one shot.
  factory Employee.fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? roleRow,
  }) {
    final scheduleRaw = row['schedule'];
    final docsRaw = row['documents'];
    final branchRaw = row['branch_ids'];

    return Employee(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
      gender: GenderX.fromDb(row['gender'] as String?),
      roleId: row['role_id'] as String?,
      role: roleRow != null ? (roleRow['name'] as String? ?? '') : '',
      email: (row['email'] as String?) ?? '',
      phone: (row['phone'] as String?) ?? '',
      hireDate: (row['hire_date'] as String?) != null
          ? DateTime.parse(row['hire_date'] as String)
          : DateTime.now(),
      status: EmployeeStatusX.fromDb(row['status'] as String?),
      employmentType:
          EmploymentTypeX.fromDb(row['employment_type'] as String?),
      compensationType:
          CompensationTypeX.fromDb(row['compensation_type'] as String?),
      hourlyRate: ((row['hourly_rate_cents'] as int?) ?? 0) / 100,
      dailyRate: ((row['daily_rate_cents'] as int?) ?? 0) / 100,
      monthlySalary: ((row['monthly_salary_cents'] as int?) ?? 0) / 100,
      branchIds: branchRaw is List
          ? branchRaw.map((e) => e.toString()).toSet()
          : <String>{},
      schedule: scheduleRaw is List
          ? scheduleRaw
              .map((e) => WorkShift.fromJson(e as Map<String, dynamic>))
              .toList()
          : <WorkShift>[],
      documents: docsRaw is List
          ? docsRaw
              .map((e) =>
                  EmployeeDocument.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EmployeeDocument>[],
      portalEnabled: (row['portal_enabled'] as bool?) ?? false,
      portalGmail: (row['portal_gmail'] as String?) ?? '',
      portalUsername: (row['portal_username'] as String?) ?? '',
      portalInvitedAt: (row['portal_invited_at'] as String?) != null
          ? DateTime.tryParse(row['portal_invited_at'] as String)
          : null,
      portalLastLoginAt: (row['portal_last_login_at'] as String?) != null
          ? DateTime.tryParse(row['portal_last_login_at'] as String)
          : null,
      notes: (row['notes'] as String?) ?? '',
      cashierPin: (row['cashier_pin'] as String?) ?? '',
    );
  }
}

class Branch {
  final String id;
  final String name;
  Branch({String? id, required this.name}) : id = id ?? _uuid.v4();
}

enum MemberTier { regular, gold }

class Member {
  final String id;
  final String name;
  final MemberTier tier;
  final bool churned;
  Member({
    String? id,
    required this.name,
    this.tier = MemberTier.regular,
    this.churned = false,
  }) : id = id ?? _uuid.v4();
}
