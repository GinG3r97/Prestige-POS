import 'dart:math';

import 'catalog.dart';
import 'employee.dart';
import 'money.dart';

enum OrderStatus { completed, refunded, voided }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.completed => 'Completed',
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

/// Deterministic mock history. Generates ~80 fake orders across the last 7
/// days using the seeded cafe products + employees. Use [generate] once at
/// app startup or whenever needed for the mockups.
class MockHistory {
  static List<MockOrder> generate({
    required List<CafeItem> products,
    required List<Employee> employees,
    String branch = 'Main Branch',
  }) {
    final rng = Random(42);
    final now = DateTime.now();
    final result = <MockOrder>[];

    final drinkProducts =
        products.where((p) => p.itemType.consumesRecipe).toList();
    if (drinkProducts.isEmpty || employees.isEmpty) return result;

    // 7 days worth — heavier today, light yesterday/earlier days.
    final hoursOfDay = [8, 9, 10, 10, 11, 11, 12, 12, 13, 14, 15, 16, 17, 18];
    for (var day = 0; day < 7; day++) {
      final dayDate = DateTime(now.year, now.month, now.day - day);
      // Modulate volume — busiest today, then yesterday, taper down.
      final volume = switch (day) {
        0 => 18,
        1 => 22,
        2 => 16,
        3 => 14,
        4 => 12,
        5 => 10,
        _ => 8,
      };
      for (var i = 0; i < volume; i++) {
        final hour = hoursOfDay[rng.nextInt(hoursOfDay.length)];
        final minute = rng.nextInt(60);
        final placedAt = DateTime(dayDate.year, dayDate.month, dayDate.day,
            hour, minute, rng.nextInt(60));

        // 1-3 lines per order
        final lineCount = 1 + rng.nextInt(3);
        final lines = <MockOrderLine>[];
        var subtotal = Money.zero;
        for (var li = 0; li < lineCount; li++) {
          final prod = drinkProducts[rng.nextInt(drinkProducts.length)];
          final qty = 1 + (rng.nextInt(100) < 25 ? 1 : 0);
          // Random modifier subtitle
          final sizes = ['Short', 'Tall', 'Grande', 'Venti'];
          final temps = ['Hot', 'Iced'];
          final subtitle =
              '${sizes[rng.nextInt(sizes.length)]} · ${temps[rng.nextInt(temps.length)]}';
          // Approximate price — base + some delta
          final delta = Money.pesos(rng.nextInt(45).toDouble());
          final unit = prod.basePrice + delta;
          final lineTotal = unit * qty;
          subtotal = subtotal + lineTotal;
          lines.add(MockOrderLine(
            name: prod.name,
            emoji: prod.emoji,
            quantity: qty,
            lineTotal: lineTotal,
            subtitle: subtitle,
          ));
        }
        // Random small discount on ~10% of orders
        final discount = rng.nextInt(100) < 10
            ? subtotal * 0.10
            : Money.zero;
        final taxedTotal = subtotal - discount;
        final vat = taxedTotal * 0.12 / 1.12;

        final emp = employees[rng.nextInt(employees.length)];
        final methodIdx = rng.nextInt(100);
        final method = methodIdx < 55
            ? PaymentMethod.cash
            : methodIdx < 78
                ? PaymentMethod.gcash
                : methodIdx < 90
                    ? PaymentMethod.qrph
                    : PaymentMethod.bank;
        final status = rng.nextInt(100) < 3
            ? OrderStatus.refunded
            : OrderStatus.completed;

        result.add(MockOrder(
          id: 'YO-${(2000 + result.length).toString().padLeft(4, '0')}',
          placedAt: placedAt,
          lines: lines,
          subtotal: subtotal,
          discount: discount,
          vat: vat,
          total: taxedTotal,
          method: method,
          status: status,
          employeeName: emp.name,
          employeeEmoji: '👤',
          branchName: branch,
        ));
      }
    }

    // Sort newest first
    result.sort((a, b) => b.placedAt.compareTo(a.placedAt));
    return result;
  }
}
