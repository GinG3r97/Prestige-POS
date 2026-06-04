/// A cashier shift (Z-reading session). Opens with a cash float, accumulates
/// sales, and closes with a counted-cash reconciliation. All money in centavos.
class CashierShift {
  final String id;
  final String status; // 'open' | 'closed'
  final String? openedByName;
  final int openingFloatCents;
  final DateTime openedAt;
  final String? closedByName;
  final DateTime? closedAt;
  final int? countedCashCents;
  final int? expectedCashCents;
  final int? overShortCents;
  final int? cashSalesCents;
  final int? totalSalesCents;
  final int? orderCount;
  // BIR Z-reading: non-resettable accumulated grand total snapshot at open /
  // close, and the reset (Z) counter for this reading.
  final int? beginningGtCents;
  final int? endingGtCents;
  final int? zCounter;

  CashierShift({
    required this.id,
    required this.status,
    this.openedByName,
    required this.openingFloatCents,
    required this.openedAt,
    this.closedByName,
    this.closedAt,
    this.countedCashCents,
    this.expectedCashCents,
    this.overShortCents,
    this.cashSalesCents,
    this.totalSalesCents,
    this.orderCount,
    this.beginningGtCents,
    this.endingGtCents,
    this.zCounter,
  });

  bool get isOpen => status == 'open';

  factory CashierShift.fromRow(Map<String, dynamic> r) => CashierShift(
        id: r['id'] as String,
        status: (r['status'] as String?) ?? 'open',
        openedByName: r['opened_by_name'] as String?,
        openingFloatCents: (r['opening_float_cents'] as int?) ?? 0,
        openedAt: DateTime.parse(r['opened_at'] as String),
        closedByName: r['closed_by_name'] as String?,
        closedAt: (r['closed_at'] as String?) != null
            ? DateTime.parse(r['closed_at'] as String)
            : null,
        countedCashCents: r['counted_cash_cents'] as int?,
        expectedCashCents: r['expected_cash_cents'] as int?,
        overShortCents: r['over_short_cents'] as int?,
        cashSalesCents: r['cash_sales_cents'] as int?,
        totalSalesCents: r['total_sales_cents'] as int?,
        orderCount: r['order_count'] as int?,
        beginningGtCents: (r['beginning_gt_cents'] as num?)?.toInt(),
        endingGtCents: (r['ending_gt_cents'] as num?)?.toInt(),
        zCounter: r['z_counter'] as int?,
      );
}

/// Live running totals for the current open shift (computed from orders since
/// it opened). Drives the Sell shift bar + the close-out Z-reading.
class ShiftTotals {
  final int cashSalesCents;
  final int cardSalesCents;
  final int otherSalesCents;
  final int totalSalesCents;
  final int orderCount;
  const ShiftTotals({
    this.cashSalesCents = 0,
    this.cardSalesCents = 0,
    this.otherSalesCents = 0,
    this.totalSalesCents = 0,
    this.orderCount = 0,
  });
}
