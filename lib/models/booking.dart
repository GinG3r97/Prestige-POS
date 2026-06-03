import 'package:flutter/material.dart';

/// What kind of thing the customer is reserving.
enum BookableKind { room, desk, space }

extension BookableKindX on BookableKind {
  String get dbValue => switch (this) {
        BookableKind.room => 'room',
        BookableKind.desk => 'desk',
        BookableKind.space => 'space',
      };

  String get label => switch (this) {
        BookableKind.room => 'Room',
        BookableKind.desk => 'Desk',
        BookableKind.space => 'Space',
      };

  IconData get icon => switch (this) {
        BookableKind.room => Icons.meeting_room_outlined,
        BookableKind.desk => Icons.chair_outlined,
        BookableKind.space => Icons.celebration_outlined,
      };

  static BookableKind fromDb(String? v) => switch (v) {
        'desk' => BookableKind.desk,
        'space' => BookableKind.space,
        _ => BookableKind.room,
      };
}

class BookableResource {
  final String id;
  String name;
  BookableKind kind;
  int capacity;
  /// Hourly rate in centavos.
  int hourlyRateCents;
  /// Hex color string ("#B07C4F") that the booking card uses on the
  /// calendar grid. Null = brand colour.
  String? color;
  String? iconName;
  int sortOrder;
  bool isActive;
  String? notes;

  BookableResource({
    required this.id,
    required this.name,
    this.kind = BookableKind.room,
    this.capacity = 1,
    this.hourlyRateCents = 0,
    this.color,
    this.iconName,
    this.sortOrder = 0,
    this.isActive = true,
    this.notes,
  });

  /// Pesos for nicer display.
  double get hourlyRatePesos => hourlyRateCents / 100.0;

  /// Booking price for a given duration. Rounds to the nearest centavo.
  int priceFor(Duration d) =>
      ((hourlyRateCents * d.inSeconds) / 3600).round();

  factory BookableResource.fromRow(Map<String, dynamic> row) =>
      BookableResource(
        id: row['id'] as String,
        name: row['name'] as String,
        kind: BookableKindX.fromDb(row['kind'] as String?),
        capacity: (row['capacity'] as int?) ?? 1,
        hourlyRateCents: (row['hourly_rate_cents'] as int?) ?? 0,
        color: row['color'] as String?,
        iconName: row['icon_name'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
        isActive: (row['is_active'] as bool?) ?? true,
        notes: row['notes'] as String?,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'name': name.trim(),
        'kind': kind.dbValue,
        'capacity': capacity,
        'hourly_rate_cents': hourlyRateCents,
        'color': color,
        'icon_name': iconName,
        'sort_order': sortOrder,
        'is_active': isActive,
        'notes': notes?.trim(),
      };
}

enum BookingStatus { confirmed, cancelled, noShow, completed }

extension BookingStatusX on BookingStatus {
  String get dbValue => switch (this) {
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.cancelled => 'cancelled',
        BookingStatus.noShow => 'no_show',
        BookingStatus.completed => 'completed',
      };

  String get label => switch (this) {
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.noShow => 'No-show',
        BookingStatus.completed => 'Completed',
      };

  static BookingStatus fromDb(String? v) => switch (v) {
        'cancelled' => BookingStatus.cancelled,
        'no_show' => BookingStatus.noShow,
        'completed' => BookingStatus.completed,
        _ => BookingStatus.confirmed,
      };
}

class Booking {
  final String id;
  String resourceId;
  String customerName;
  String? customerPhone;
  DateTime startsAt;
  /// `null` means the booking is an **open session** — a walk-in
  /// customer is still sitting and the cashier hasn't stopped the
  /// timer yet. A scheduled reservation always has a concrete
  /// [endsAt]. See [isOpenSession].
  DateTime? endsAt;
  BookingStatus status;
  int priceCents;
  String? notes;

  Booking({
    required this.id,
    required this.resourceId,
    required this.customerName,
    this.customerPhone,
    required this.startsAt,
    this.endsAt,
    this.status = BookingStatus.confirmed,
    this.priceCents = 0,
    this.notes,
  });

  /// Open sessions (walk-ins) have no end time yet.
  bool get isOpenSession =>
      endsAt == null && status == BookingStatus.confirmed;

  /// For closed bookings, the booked length; for open sessions, the
  /// elapsed time since check-in.
  Duration get duration =>
      (endsAt ?? DateTime.now()).difference(startsAt);

  double get pricePesos => priceCents / 100.0;

  /// Convenience — true if [other] overlaps this booking on the same
  /// resource. Open sessions are treated as extending to "forever"
  /// for conflict purposes so they block any future reservation on
  /// the same resource until they're closed.
  bool overlaps(DateTime otherStart, DateTime otherEnd) {
    if (!startsAt.isBefore(otherEnd)) return false;
    return endsAt == null || endsAt!.isAfter(otherStart);
  }

  factory Booking.fromRow(Map<String, dynamic> row) => Booking(
        id: row['id'] as String,
        resourceId: row['resource_id'] as String,
        customerName: (row['customer_name'] as String?) ?? '',
        customerPhone: row['customer_phone'] as String?,
        startsAt: DateTime.parse(row['starts_at'] as String).toLocal(),
        endsAt: row['ends_at'] == null
            ? null
            : DateTime.parse(row['ends_at'] as String).toLocal(),
        status: BookingStatusX.fromDb(row['status'] as String?),
        priceCents: (row['price_cents'] as int?) ?? 0,
        notes: row['notes'] as String?,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'resource_id': resourceId,
        'customer_name': customerName.trim(),
        'customer_phone': customerPhone?.trim(),
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'status': status.dbValue,
        'price_cents': priceCents,
        'notes': notes?.trim(),
      };
}

/// Rounds an open session's elapsed window UP to the nearest 15
/// minutes — the rule we promise on screen ("rounded up to 15 min").
/// Always returns at least the 15-minute minimum so a customer who
/// sits for 4 minutes still pays a base.
({DateTime endsAt, Duration billed}) roundSessionEnd(
    DateTime startsAt, DateTime closeAt) {
  final elapsed = closeAt.difference(startsAt);
  // Minimum bill = 15 min; round up to the next 15-min increment.
  final units = (elapsed.inSeconds / (15 * 60)).ceil();
  final billed = Duration(minutes: 15 * (units < 1 ? 1 : units));
  return (endsAt: startsAt.add(billed), billed: billed);
}
