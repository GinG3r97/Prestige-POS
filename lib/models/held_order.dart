import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// One line of a held (parked) order, stored by reference so it can be
/// re-resolved against the live catalog when resumed (prices stay current).
class HeldLine {
  final String itemId;
  final int quantity;
  final Map<String, String> selections; // groupId -> optionId
  final Map<String, int> addOns; // addOnId -> quantity

  HeldLine({
    required this.itemId,
    required this.quantity,
    Map<String, String>? selections,
    Map<String, int>? addOns,
  })  : selections = selections ?? const {},
        addOns = addOns ?? const {};

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'qty': quantity,
        'sel': selections,
        'add': addOns,
      };

  factory HeldLine.fromJson(Map<String, dynamic> j) => HeldLine(
        itemId: j['itemId'] as String,
        quantity: (j['qty'] as num).toInt(),
        selections: (j['sel'] as Map?)
                ?.map((k, v) => MapEntry(k as String, v as String)) ??
            const {},
        addOns: (j['add'] as Map?)
                ?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ??
            const {},
      );
}

/// A parked order the cashier set aside to serve later. The total/itemCount are
/// cached for the list display; the real cart is rebuilt from [lines] on resume.
class HeldOrder {
  final String id;
  final String label;
  final int savedAtMs;
  final List<HeldLine> lines;
  final int itemCount;
  final int totalCents;

  HeldOrder({
    String? id,
    required this.label,
    required this.savedAtMs,
    required this.lines,
    required this.itemCount,
    required this.totalCents,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'at': savedAtMs,
        'count': itemCount,
        'total': totalCents,
        'lines': [for (final l in lines) l.toJson()],
      };

  factory HeldOrder.fromJson(Map<String, dynamic> j) => HeldOrder(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? '',
        savedAtMs: (j['at'] as num?)?.toInt() ?? 0,
        itemCount: (j['count'] as num?)?.toInt() ?? 0,
        totalCents: (j['total'] as num?)?.toInt() ?? 0,
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            HeldLine.fromJson(l as Map<String, dynamic>),
        ],
      );
}
