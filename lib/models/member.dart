import 'package:flutter/material.dart';

/// What kind of plan template is this? Drives how `units_remaining`
/// is interpreted and how renewal works.
///
/// - [monthly]: unlimited use until `expiresAt`. No unit balance.
/// - [hours]: prepaid bundle of minutes. Each booking/session deducts.
/// - [passes]: prepaid day-passes. One pass = one day of use.
enum MemberPlanKind { monthly, hours, passes }

extension MemberPlanKindX on MemberPlanKind {
  String get dbValue => switch (this) {
        MemberPlanKind.monthly => 'monthly',
        MemberPlanKind.hours => 'hours',
        MemberPlanKind.passes => 'passes',
      };

  String get label => switch (this) {
        MemberPlanKind.monthly => 'Monthly',
        MemberPlanKind.hours => 'Hour pack',
        MemberPlanKind.passes => 'Day-pass pack',
      };

  String get description => switch (this) {
        MemberPlanKind.monthly =>
          'Recurring monthly subscription — unlimited use until renewal.',
        MemberPlanKind.hours =>
          'Prepaid bundle of hours. Each session deducts minutes.',
        MemberPlanKind.passes =>
          'Prepaid bundle of day-passes. One pass = one day of use.',
      };

  IconData get icon => switch (this) {
        MemberPlanKind.monthly => Icons.calendar_month_outlined,
        MemberPlanKind.hours => Icons.schedule,
        MemberPlanKind.passes => Icons.confirmation_number_outlined,
      };

  /// Human-readable label for what one unit means on this plan kind.
  /// Used in the dialog labels and balance pills.
  String get unitsLabel => switch (this) {
        MemberPlanKind.monthly => 'units',
        MemberPlanKind.hours => 'minutes',
        MemberPlanKind.passes => 'passes',
      };

  static MemberPlanKind fromDb(String? v) => switch (v) {
        'hours' => MemberPlanKind.hours,
        'passes' => MemberPlanKind.passes,
        _ => MemberPlanKind.monthly,
      };
}

class MemberPlan {
  final String id;
  String name;
  MemberPlanKind kind;
  int priceCents;
  int durationDays;
  /// For [hours] = minutes included (e.g. 10 hours → 600). For
  /// [passes] = passes included. For [monthly] = null (unlimited).
  int? includedUnits;
  List<String> perks;
  String? color;
  String? iconName;
  int sortOrder;
  bool isActive;
  String? notes;

  MemberPlan({
    required this.id,
    required this.name,
    this.kind = MemberPlanKind.monthly,
    this.priceCents = 0,
    this.durationDays = 30,
    this.includedUnits,
    this.perks = const [],
    this.color,
    this.iconName,
    this.sortOrder = 100,
    this.isActive = true,
    this.notes,
  });

  double get pricePesos => priceCents / 100.0;

  /// Pretty inline summary used in tiles and pickers.
  String get summary {
    final price = '₱${pricePesos.toStringAsFixed(0)}';
    switch (kind) {
      case MemberPlanKind.monthly:
        return '$price / $durationDays days · unlimited';
      case MemberPlanKind.hours:
        final hrs = ((includedUnits ?? 0) / 60).toStringAsFixed(
            (includedUnits ?? 0) % 60 == 0 ? 0 : 1);
        return '$price · ${hrs}h, $durationDays-day expiry';
      case MemberPlanKind.passes:
        return '$price · ${includedUnits ?? 0} passes, '
            '$durationDays-day expiry';
    }
  }

  factory MemberPlan.fromRow(Map<String, dynamic> row) => MemberPlan(
        id: row['id'] as String,
        name: row['name'] as String,
        kind: MemberPlanKindX.fromDb(row['kind'] as String?),
        priceCents: (row['price_cents'] as int?) ?? 0,
        durationDays: (row['duration_days'] as int?) ?? 30,
        includedUnits: row['included_units'] as int?,
        perks: ((row['perks'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        color: row['color'] as String?,
        iconName: row['icon_name'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 100,
        isActive: (row['is_active'] as bool?) ?? true,
        notes: row['notes'] as String?,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'name': name.trim(),
        'kind': kind.dbValue,
        'price_cents': priceCents,
        'duration_days': durationDays,
        'included_units': includedUnits,
        'perks': perks,
        'color': color,
        'icon_name': iconName,
        'sort_order': sortOrder,
        'is_active': isActive,
        'notes': notes?.trim(),
      };
}

/// Lifecycle status for a member. Drives the roster filter chips and
/// which actions are available.
///
/// - [active]: plan has time / units left and hasn't expired.
/// - [lapsed]: plan expired or balance hit zero, but the member
///   hasn't formally cancelled. Owner can prompt a renewal.
/// - [churned]: member cancelled or owner archived them.
enum MemberStatus { active, lapsed, churned }

extension MemberStatusX on MemberStatus {
  String get dbValue => switch (this) {
        MemberStatus.active => 'active',
        MemberStatus.lapsed => 'lapsed',
        MemberStatus.churned => 'churned',
      };

  String get label => switch (this) {
        MemberStatus.active => 'Active',
        MemberStatus.lapsed => 'Lapsed',
        MemberStatus.churned => 'Churned',
      };

  Color get tone => switch (this) {
        MemberStatus.active => const Color(0xFF5C8A6B),
        MemberStatus.lapsed => const Color(0xFFC29A36),
        MemberStatus.churned => const Color(0xFF8A8A8A),
      };

  static MemberStatus fromDb(String? v) => switch (v) {
        'lapsed' => MemberStatus.lapsed,
        'churned' => MemberStatus.churned,
        _ => MemberStatus.active,
      };
}

class Member {
  final String id;
  String fullName;
  String? phone;
  String? email;
  String? photoUrl;
  String? planId;
  DateTime? planStartedAt;
  DateTime? planExpiresAt;
  int? unitsRemaining;
  MemberStatus status;
  DateTime joinedAt;
  String? notes;

  Member({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.photoUrl,
    this.planId,
    this.planStartedAt,
    this.planExpiresAt,
    this.unitsRemaining,
    this.status = MemberStatus.active,
    DateTime? joinedAt,
    this.notes,
  }) : joinedAt = joinedAt ?? DateTime.now();

  /// `null` = no expiry (monthly plan without a set expiry, or no
  /// plan). Otherwise days from now until the plan ends. Negative
  /// means already expired.
  int? get daysUntilExpiry {
    if (planExpiresAt == null) return null;
    return planExpiresAt!.difference(DateTime.now()).inDays;
  }

  /// Is the member's plan winding down (≤7 days left)? Drives the
  /// "Expiring soon" filter chip on the roster.
  bool get isExpiringSoon {
    final d = daysUntilExpiry;
    return d != null && d >= 0 && d <= 7;
  }

  bool get isExpired {
    final d = daysUntilExpiry;
    return d != null && d < 0;
  }

  /// Display string for the member card balance section. Format
  /// depends on the plan kind, which we derive from the linked
  /// [plan] (if available) or fall back to "—".
  String balanceDisplay(MemberPlan? plan) {
    if (plan == null) return 'No plan';
    switch (plan.kind) {
      case MemberPlanKind.monthly:
        final d = daysUntilExpiry;
        if (d == null) return 'Active';
        if (d < 0) return 'Expired ${(-d)} d ago';
        if (d == 0) return 'Expires today';
        return 'Renews in $d d';
      case MemberPlanKind.hours:
        final mins = unitsRemaining ?? 0;
        final hrs = (mins / 60);
        if (hrs == 0) return '0 min left';
        if (hrs >= 1) {
          return hrs % 1 == 0
              ? '${hrs.toInt()}h left'
              : '${hrs.toStringAsFixed(1)}h left';
        }
        return '$mins min left';
      case MemberPlanKind.passes:
        final n = unitsRemaining ?? 0;
        return n == 1 ? '1 pass left' : '$n passes left';
    }
  }

  /// 0..1 fraction of the plan still available, used to draw a
  /// progress bar on the member card. For monthly = days-left /
  /// duration. For hours/passes = units-left / included.
  double balanceFraction(MemberPlan? plan) {
    if (plan == null) return 0.0;
    switch (plan.kind) {
      case MemberPlanKind.monthly:
        final d = daysUntilExpiry;
        if (d == null || d < 0) return 0.0;
        final span = plan.durationDays;
        if (span <= 0) return 0.0;
        return (d / span).clamp(0.0, 1.0);
      case MemberPlanKind.hours:
      case MemberPlanKind.passes:
        final inc = plan.includedUnits ?? 0;
        if (inc <= 0) return 0.0;
        final left = unitsRemaining ?? 0;
        return (left / inc).clamp(0.0, 1.0);
    }
  }

  factory Member.fromRow(Map<String, dynamic> row) => Member(
        id: row['id'] as String,
        fullName: (row['full_name'] as String?) ?? '',
        phone: row['phone'] as String?,
        email: row['email'] as String?,
        photoUrl: row['photo_url'] as String?,
        planId: row['plan_id'] as String?,
        planStartedAt: row['plan_started_at'] == null
            ? null
            : DateTime.parse(row['plan_started_at'] as String).toLocal(),
        planExpiresAt: row['plan_expires_at'] == null
            ? null
            : DateTime.parse(row['plan_expires_at'] as String).toLocal(),
        unitsRemaining: row['units_remaining'] as int?,
        status: MemberStatusX.fromDb(row['status'] as String?),
        joinedAt: row['joined_at'] == null
            ? DateTime.now()
            : DateTime.parse(row['joined_at'] as String).toLocal(),
        notes: row['notes'] as String?,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'full_name': fullName.trim(),
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'email': (email ?? '').trim().isEmpty ? null : email!.trim(),
        'photo_url': photoUrl,
        'plan_id': planId,
        'plan_started_at': planStartedAt?.toUtc().toIso8601String(),
        'plan_expires_at': planExpiresAt?.toUtc().toIso8601String(),
        'units_remaining': unitsRemaining,
        'status': status.dbValue,
        'joined_at': joinedAt.toUtc().toIso8601String(),
        'notes': notes?.trim(),
      };
}
