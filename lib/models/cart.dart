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

class CartLineCafe extends CartLineKind {
  final CafeItem item;
  final Map<String, String> selections; // groupId -> optionId
  /// Add-ons chosen by the customer at order time (snapshot of the AddOn).
  final List<CartAddOn> addOns;

  CartLineCafe(this.item, this.selections, {List<CartAddOn>? addOns})
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
      };

  String? get subtitle => switch (kind) {
        CartLineCafe(:final item, :final selections, :final addOns) => () {
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
            return parts.isEmpty ? item.subtitle : parts.join(' · ');
          }(),
      };

  String get emoji => switch (kind) {
        CartLineCafe(:final item) => item.emoji,
      };

  String? get imageUrl => switch (kind) {
        CartLineCafe(:final item) => item.imageUrl,
      };

  String? get iconName => switch (kind) {
        CartLineCafe(:final item) => item.iconName,
      };

  Money get unitPrice => switch (kind) {
        CartLineCafe(:final item, :final selections, :final addOns) => () {
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
      };

  Money get lineTotal => unitPrice * quantity;
}

class CartStore extends ChangeNotifier {
  final List<CartLine> lines = [];
  Member? customer;

  Money get subtotal =>
      lines.fold(Money.zero, (acc, l) => acc + l.lineTotal);

  Money get memberDiscount =>
      customer?.tier == MemberTier.gold ? subtotal * 0.05 : Money.zero;

  Money get vat => (subtotal - memberDiscount) * 0.12 / 1.12;

  Money get total => subtotal - memberDiscount;

  int get itemCount => lines.fold(0, (acc, l) => acc + l.quantity);

  void addCafe(
    CafeItem item,
    Map<String, String> selections, {
    int quantity = 1,
    List<CartAddOn>? addOns,
  }) {
    if (quantity < 1) return;
    final cleanAddOns = (addOns ?? <CartAddOn>[])
        .where((a) => a.quantity > 0)
        .toList();

    final existing = lines.indexWhere((l) {
      if (l.kind case CartLineCafe(
        item: final lineItem,
        selections: final s,
        addOns: final ao,
      )) {
        return lineItem.id == item.id &&
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
          kind: CartLineCafe(item, selections, addOns: cleanAddOns),
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
    lines.removeWhere((l) => l.id == line.id);
    notifyListeners();
  }

  void setQuantity(CartLine line, int qty) {
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
