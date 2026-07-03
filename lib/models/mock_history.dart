import 'money.dart';

enum OrderStatus { completed, unpaid, refunded, voided }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.completed => 'Completed',
        OrderStatus.unpaid => 'Unpaid',
        OrderStatus.refunded => 'Refunded',
        OrderStatus.voided => 'Voided',
      };
}

enum PaymentMethod { cash, gcash, bank, qrph, other }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.bank => 'Bank',
        PaymentMethod.qrph => 'QR Ph',
        PaymentMethod.other => 'Other',
      };
}

/// Lightweight order line for the mock history.
class MockOrderLine {
  final String name;
  final String emoji;
  final int quantity;
  final Money lineTotal;
  final String? subtitle; // size · temp · add-ons summary

  /// Category name snapshot — used to render the on-theme category icon
  /// (food → restaurant, books → book) instead of a colourful emoji.
  final String? categoryName;

  /// Real DB order_line id — null for legacy mock data. Needed to void/refund
  /// a single item.
  final String? lineId;

  /// True when this line was voided/refunded individually.
  final bool reversed;

  /// 'Voided' / 'Refunded' for a reversed line; null otherwise.
  final String? reversedLabel;

  MockOrderLine({
    required this.name,
    required this.emoji,
    required this.quantity,
    required this.lineTotal,
    this.subtitle,
    this.categoryName,
    this.lineId,
    this.reversed = false,
    this.reversedLabel,
  });
}

class MockOrder {
  final String id;
  final DateTime placedAt;
  final List<MockOrderLine> lines;
  final Money subtotal;
  final Money discount;
  final Money vat;
  final Money total;
  final PaymentMethod method;
  final OrderStatus status;
  final String employeeName;
  final String employeeEmoji;
  final String branchName;

  MockOrder({
    required this.id,
    required this.placedAt,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.vat,
    required this.total,
    required this.method,
    required this.status,
    required this.employeeName,
    required this.employeeEmoji,
    required this.branchName,
  });

  int get itemCount => lines.fold(0, (a, l) => a + l.quantity);
}

