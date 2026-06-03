/// Money-layer domain models — mirror rows from `public.orders`,
/// `public.order_lines`, `public.payments`. All money is stored as
/// integer centavos; the Money class handles formatting.

enum OrderStatus { open, paid, voided, refunded, cancelled }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.open => 'Open',
        OrderStatus.paid => 'Paid',
        OrderStatus.voided => 'Voided',
        OrderStatus.refunded => 'Refunded',
        OrderStatus.cancelled => 'Cancelled',
      };

  static OrderStatus fromString(String s) => switch (s) {
        'paid' => OrderStatus.paid,
        'voided' => OrderStatus.voided,
        'refunded' => OrderStatus.refunded,
        'cancelled' => OrderStatus.cancelled,
        _ => OrderStatus.open,
      };
}

enum OrderPaymentMethod { cash, gcash, paymaya, card, bankTransfer, other }

extension OrderPaymentMethodX on OrderPaymentMethod {
  String get label => switch (this) {
        OrderPaymentMethod.cash => 'Cash',
        OrderPaymentMethod.gcash => 'GCash',
        OrderPaymentMethod.paymaya => 'PayMaya',
        OrderPaymentMethod.card => 'Card',
        OrderPaymentMethod.bankTransfer => 'Bank Transfer',
        OrderPaymentMethod.other => 'Other',
      };

  /// Token used in the `payments.method` column (matches the SQL CHECK).
  String get dbValue => switch (this) {
        OrderPaymentMethod.cash => 'cash',
        OrderPaymentMethod.gcash => 'gcash',
        OrderPaymentMethod.paymaya => 'paymaya',
        OrderPaymentMethod.card => 'card',
        OrderPaymentMethod.bankTransfer => 'bank_transfer',
        OrderPaymentMethod.other => 'other',
      };

  static OrderPaymentMethod fromString(String s) => switch (s) {
        'cash' => OrderPaymentMethod.cash,
        'gcash' => OrderPaymentMethod.gcash,
        'paymaya' => OrderPaymentMethod.paymaya,
        'card' => OrderPaymentMethod.card,
        'bank_transfer' => OrderPaymentMethod.bankTransfer,
        _ => OrderPaymentMethod.other,
      };
}

/// A line item snapshot — what was sold, at what price, with which modifiers.
/// Fields are snapshotted at sale time so the receipt survives later product
/// edits/deletes.
/// Reversal state of a single order line. 'active' = counts toward the
/// order; 'voided'/'refunded' = pulled by a per-item void/refund.
enum OrderLineStatus { active, voided, refunded }

extension OrderLineStatusX on OrderLineStatus {
  bool get isReversed => this != OrderLineStatus.active;
  String get label => switch (this) {
        OrderLineStatus.active => 'Active',
        OrderLineStatus.voided => 'Voided',
        OrderLineStatus.refunded => 'Refunded',
      };
  static OrderLineStatus fromString(String? s) => switch (s) {
        'voided' => OrderLineStatus.voided,
        'refunded' => OrderLineStatus.refunded,
        _ => OrderLineStatus.active,
      };
}

class OrderLine {
  final String id;
  final String? sellableId;
  final String name;
  final String? categoryName;
  final String emoji;
  final int unitPriceCents;
  final int quantity;
  final int lineTotalCents;
  final Map<String, dynamic>? modifiers;
  final OrderLineStatus status;
  final String? reverseReason;

  OrderLine({
    required this.id,
    this.sellableId,
    required this.name,
    this.categoryName,
    this.emoji = '',
    required this.unitPriceCents,
    required this.quantity,
    required this.lineTotalCents,
    this.modifiers,
    this.status = OrderLineStatus.active,
    this.reverseReason,
  });

  factory OrderLine.fromRow(Map<String, dynamic> row) => OrderLine(
        id: row['id'] as String,
        sellableId: row['sellable_id'] as String?,
        name: row['sellable_name'] as String,
        categoryName: row['category_name'] as String?,
        emoji: (row['emoji'] as String?) ?? '',
        unitPriceCents: (row['unit_price_cents'] as int?) ?? 0,
        quantity: (row['quantity'] as int?) ?? 1,
        lineTotalCents: (row['line_total_cents'] as int?) ?? 0,
        modifiers: row['modifiers_json'] as Map<String, dynamic>?,
        status: OrderLineStatusX.fromString(row['status'] as String?),
        reverseReason: row['reverse_reason'] as String?,
      );
}

/// A tender — one row per payment method used on an order. A ₱500 order
/// paid with ₱200 cash + ₱300 GCash is two payment rows.
class OrderPayment {
  final String id;
  final OrderPaymentMethod method;
  final int amountCents;
  final int? tenderedCents;
  final int? changeCents;
  final String? reference;
  final bool refunded;

  OrderPayment({
    required this.id,
    required this.method,
    required this.amountCents,
    this.tenderedCents,
    this.changeCents,
    this.reference,
    this.refunded = false,
  });

  factory OrderPayment.fromRow(Map<String, dynamic> row) => OrderPayment(
        id: row['id'] as String,
        method: OrderPaymentMethodX.fromString(row['method'] as String),
        amountCents: (row['amount_cents'] as int?) ?? 0,
        tenderedCents: row['tendered_cents'] as int?,
        changeCents: row['change_cents'] as int?,
        reference: row['reference'] as String?,
        refunded: (row['refunded'] as bool?) ?? false,
      );
}

/// An order — the header. Has many [OrderLine]s and [OrderPayment]s.
class Order {
  final String id;
  final String tenantId;
  final String? branchId;
  final String? cashierId;
  final String? cashierName;
  final int orderNumber;
  final OrderStatus status;
  final int subtotalCents;
  final int discountCents;
  final int vatCents;
  final int totalCents;
  final String? customerName;
  final String? customerPhone;
  final String? notes;
  final String? voidReason;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? voidedAt;

  /// Populated by the fetch-with-relations query. Empty list when the
  /// order is fetched without joining lines/payments.
  final List<OrderLine> lines;
  final List<OrderPayment> payments;

  Order({
    required this.id,
    required this.tenantId,
    this.branchId,
    this.cashierId,
    this.cashierName,
    required this.orderNumber,
    required this.status,
    required this.subtotalCents,
    this.discountCents = 0,
    this.vatCents = 0,
    required this.totalCents,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.voidReason,
    required this.createdAt,
    this.paidAt,
    this.voidedAt,
    this.lines = const [],
    this.payments = const [],
  });

  factory Order.fromRow(Map<String, dynamic> row, {
    List<OrderLine> lines = const [],
    List<OrderPayment> payments = const [],
  }) =>
      Order(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        branchId: row['branch_id'] as String?,
        cashierId: row['cashier_id'] as String?,
        cashierName: row['cashier_name'] as String?,
        orderNumber: (row['order_number'] as int?) ?? 0,
        status: OrderStatusX.fromString(row['status'] as String? ?? 'open'),
        subtotalCents: (row['subtotal_cents'] as int?) ?? 0,
        discountCents: (row['discount_cents'] as int?) ?? 0,
        vatCents: (row['vat_cents'] as int?) ?? 0,
        totalCents: (row['total_cents'] as int?) ?? 0,
        customerName: row['customer_name'] as String?,
        customerPhone: row['customer_phone'] as String?,
        notes: row['notes'] as String?,
        voidReason: row['void_reason'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        paidAt: row['paid_at'] == null
            ? null
            : DateTime.parse(row['paid_at'] as String),
        voidedAt: row['voided_at'] == null
            ? null
            : DateTime.parse(row['voided_at'] as String),
        lines: lines,
        payments: payments,
      );
}
