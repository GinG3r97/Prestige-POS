import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'money.dart';
import 'catalog.dart';
import 'employee.dart';

const _uuid = Uuid();

sealed class CartLineKind {}

/// A single add-on attached to a cart line, with its own quantity.
class CartAddOn {
  final AddOn addOn;
  final int quantity;
  CartAddOn(this.addOn, this.quantity);
}

/// A read-only line loaded from an existing unpaid (pay-later) order so the
/// cashier can settle it through the normal checkout. Not editable, never
/// merges, and carries no recipe — stock was already deducted when the
/// order was fired.
class CartLineSettle extends CartLineKind {
  final String name;
  final String? detail;
  final String emojiChar;
  final int unitPriceCents;
  CartLineSettle({
    required this.name,
    this.detail,
    this.emojiChar = '',
    required this.unitPriceCents,
  });
}

class CartLineCafe extends CartLineKind {
  final CafeItem item;
  final Map<String, String> selections; // groupId -> optionId
  /// Add-ons chosen by the customer at order time (snapshot of the AddOn).
  final List<CartAddOn> addOns;

  /// For "Custom price" products — the unit price the cashier typed at
  /// checkout. When set it replaces the computed price entirely.
  final Money? priceOverride;

  /// Optional free-text note captured in the product modal (e.g. "2.5 kg").
  final String? note;

  CartLineCafe(this.item, this.selections,
      {List<CartAddOn>? addOns, this.priceOverride, this.note})
      : addOns = addOns ?? <CartAddOn>[];

  /// Convenience: map of addOnId -> quantity for [AppState.expandRecipe].
  Map<String, int> get addOnQuantities =>
      {for (final a in addOns) a.addOn.id: a.quantity};
}

class CartLine {
  final String id;
  final CartLineKind kind;
  int quantity;

  CartLine({String? id, required this.kind, this.quantity = 1})
      : id = id ?? _uuid.v4();

  String get title => switch (kind) {
        CartLineCafe(:final item) => item.name,
        CartLineSettle(:final name) => name,
      };

  String? get subtitle => switch (kind) {
        CartLineCafe(:final item, :final selections, :final addOns, :final note) =>
          () {
            final parts = item.modifierGroups
                .map((g) {
                  final optId = selections[g.id];
                  if (optId == null) return null;
                  final opt =
                      g.options.where((o) => o.id == optId).firstOrNull;
                  return opt?.name;
                })
                .whereType<String>()
                .toList();
            for (final a in addOns) {
              if (a.quantity <= 0) continue;
              parts.add(a.quantity > 1
                  ? '+${a.addOn.name} ×${a.quantity}'
                  : '+${a.addOn.name}');
            }
            final base = parts.isEmpty ? item.subtitle : parts.join(' · ');
            final n = note?.trim() ?? '';
            if (n.isEmpty) return base;
            return base.isEmpty ? '📝 $n' : '$base · 📝 $n';
          }(),
        CartLineSettle(:final detail) => detail,
      };

  String get emoji => switch (kind) {
        CartLineCafe(:final item) => item.emoji,
        CartLineSettle(:final emojiChar) => emojiChar,
      };

  String? get imageUrl => switch (kind) {
        CartLineCafe(:final item) => item.imageUrl,
        CartLineSettle() => null,
      };

  String? get iconName => switch (kind) {
        CartLineCafe(:final item) => item.iconName,
        CartLineSettle() => null,
      };

  Money get unitPrice => switch (kind) {
        CartLineCafe(
          :final item,
          :final selections,
          :final addOns,
          :final priceOverride
        ) =>
          () {
            // Custom-price line — the typed price is the whole unit price.
            if (priceOverride != null) return priceOverride;
            var total = item.basePrice;
            // Global per-option price (Maintenance → Modifier groups).
            for (final g in item.modifierGroups) {
              final optId = selections[g.id];
              if (optId == null) continue;
              final opt =
                  g.options.where((o) => o.id == optId).firstOrNull;
              if (opt != null) total = total + opt.priceDelta;
            }
            // Per-product per-option price (Products form → Recipe tab →
            // Size/Temperature/Strength tab → option row).
            for (final adj in item.modifierAdjustments) {
              if (selections[adj.groupId] != adj.optionId) continue;
              total = total + adj.priceDelta;
            }
            for (final a in addOns) {
              if (a.quantity <= 0) continue;
              total = total + (a.addOn.priceDelta * a.quantity);
            }
            return total;
          }(),
        CartLineSettle(:final unitPriceCents) => Money(unitPriceCents),
      };

  Money get lineTotal => unitPrice * quantity;
}

class CartStore extends ChangeNotifier {
  final List<CartLine> lines = [];
  Member? customer;

  Money get subtotal =>
      lines.fold(Money.zero, (acc, l) => acc + l.lineTotal);

  // NOTE: member-tier auto-discount isn't wired end-to-end (no UI attaches a
  // member, and it wasn't passed to create_paid_order), so the cart total is
  // the plain subtotal. Re-introduce a discount only by routing it through
  // createPaidOrder's discountCents to keep the charged amount consistent.
  Money get vat => subtotal * 0.12 / 1.12;

  Money get total => subtotal;

  int get itemCount => lines.fold(0, (acc, l) => acc + l.quantity);

  /// True while the cart holds lines loaded from unpaid orders being
  /// settled — the cart is then read-only until paid or cleared.
  bool get isSettling => lines.any((l) => l.kind is CartLineSettle);

  /// Replaces the cart with read-only lines from the unpaid orders being
  /// settled (pay-later flow). The cashier pays through normal checkout.
  void loadForSettle(List<CartLine> settleLines) {
    lines
      ..clear()
      ..addAll(settleLines);
    customer = null;
    notifyListeners();
  }

  void addCafe(
    CafeItem item,
    Map<String, String> selections, {
    int quantity = 1,
    List<CartAddOn>? addOns,
    Money? priceOverride,
    String? note,
  }) {
    if (quantity < 1) return;
    // A settle cart is frozen — finish or cancel settling before selling.
    if (isSettling) return;
    final cleanAddOns = (addOns ?? <CartAddOn>[])
        .where((a) => a.quantity > 0)
        .toList();

    // Custom-price lines (and any with a note) stand alone — never merge, so a
    // ₱120 book and a ₱200 book stay separate.
    final existing = (priceOverride != null || (note?.trim().isNotEmpty ?? false))
        ? -1
        : lines.indexWhere((l) {
            if (l.kind case CartLineCafe(
              item: final lineItem,
              selections: final s,
              addOns: final ao,
              priceOverride: final po,
            )) {
              return po == null &&
                  lineItem.id == item.id &&
                  _mapsEqual(s, selections) &&
                  _addOnsEqual(ao, cleanAddOns);
            }
            return false;
          });
    if (existing >= 0) {
      lines[existing].quantity += quantity;
    } else {
      lines.add(
        CartLine(
          kind: CartLineCafe(item, selections,
              addOns: cleanAddOns, priceOverride: priceOverride, note: note),
          quantity: quantity,
        ),
      );
    }
    notifyListeners();
  }

  bool _addOnsEqual(List<CartAddOn> a, List<CartAddOn> b) {
    if (a.length != b.length) return false;
    final aMap = {for (final x in a) x.addOn.id: x.quantity};
    final bMap = {for (final x in b) x.addOn.id: x.quantity};
    return _intMapsEqual(aMap, bMap);
  }

  void remove(CartLine line) {
    // Settle carts are all-or-nothing — the cashier either pays the whole
    // tab or clears it. Removing one line would desync the settle order ids.
    if (isSettling) return;
    lines.removeWhere((l) => l.id == line.id);
    notifyListeners();
  }

  void setQuantity(CartLine line, int qty) {
    if (isSettling) return;
    final idx = lines.indexWhere((l) => l.id == line.id);
    if (idx < 0) return;
    if (qty <= 0) {
      lines.removeAt(idx);
    } else {
      lines[idx].quantity = qty;
    }
    notifyListeners();
  }

  void clear() {
    lines.clear();
    customer = null;
    notifyListeners();
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  bool _intMapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
