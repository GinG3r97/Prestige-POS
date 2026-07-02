import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../data/supabase_client.dart';
import '../../models/inventory.dart';

/// Owns the Inventory domain (inventory items + inventory categories),
/// extracted from the monolithic [AppState] so that the rest of the app
/// watching AppState no longer rebuilds when a stock row changes. Inventory
/// feature screens (Stock, the inventory form, the low-stock dashboard tile,
/// the recipe ingredient picker, Maintenance inventory-categories tab, the
/// Reports inventory lens) watch this store directly via its own provider.
///
/// AppState owns a single instance ([AppState.inv]) and drives its lifecycle
/// via [hydrate] (on tenant restore) and [reset] (on sign-out / tenant
/// switch). The Supabase calls, sorting, and notify timing are identical to
/// what AppState used to do inline.
///
/// This domain is money-path coupled — CHECKOUT deducts stock — so the
/// deduction stays a coordinator on AppState ([deductCartFromInventory]) that
/// reads the cart + catalog and then mutates inventory THROUGH
/// [applyDeductions] here. The stock-read coordinators
/// (canFulfillOne/buildableCount/validateCartStock/projectedCartDeductions)
/// also stay on AppState and read [inventory] off this store. The void/refund
/// restock flow re-fetches from the DB and hands the rows to [replaceItems].
class InventoryStore extends ChangeNotifier {
  /// The active tenant DB id, set by [hydrate]. All mutations are scoped to
  /// this tenant. `null` means no store is selected (signed out / no tenant).
  /// Mirrors what AppState called `_currentTenantDbId`.
  String? _tenantId;

  // ───── inventory categories (Supabase-backed) ─────────────────────

  /// Owners manage these in Maintenance → Inventory categories.
  /// `inventory_items.inventory_category_id` is the canonical FK.
  List<InventoryCategory> _inventoryCategories = [];
  List<InventoryCategory> get inventoryCategories =>
      List.unmodifiable(_inventoryCategories);

  /// Lookup helper — returns null if the id isn't in the cache (e.g. the
  /// category was just deleted while items still reference it; UI falls
  /// back to the denormalized text `inventory_items.category`).
  InventoryCategory? inventoryCategoryById(String? id) {
    if (id == null) return null;
    for (final c in _inventoryCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ───── inventory (Supabase-backed) ───────────────────────────────

  List<InventoryItem> _inventory = [];
  List<InventoryItem> get inventory => List.unmodifiable(_inventory);

  int get lowStockCount => _inventory.where((i) => i.isLowStock).length;

  // ───── lifecycle ─────

  /// Loads inventory categories + inventory items for [tenantId] from
  /// Supabase, then notifies. Called by AppState during tenant hydration.
  /// Same order/sort AppState used inline (categories by sort_order, items by
  /// name).
  Future<void> hydrate(String tenantId) async {
    _tenantId = tenantId;
    final tid = tenantId as Object;
    await Future.wait<void>([
      () async {
        final invCatRows = await supabase
            .from('inventory_categories')
            .select('*')
            .eq('tenant_id', tid)
            .order('sort_order');
        _inventoryCategories = (invCatRows as List)
            .map((r) => InventoryCategory.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
      () async {
        final invRows = await supabase
            .from('inventory_items')
            .select('*')
            .eq('tenant_id', tid)
            .order('name');
        _inventory = (invRows as List)
            .map((r) => InventoryItem.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
    ]);
    notifyListeners();
  }

  /// Clears the active-tenant inventory view (sign-out / tenant switch).
  /// Mirrors the old AppState reset which wiped both lists.
  void reset() {
    _tenantId = null;
    _inventory = [];
    _inventoryCategories = [];
    notifyListeners();
  }

  /// Applies the checkout coordinator's per-item deductions to the local
  /// inventory cache. Each entry is `inventoryItemId -> quantity to remove`.
  /// The DB-side `create_paid_order` RPC also deducts server-side so the
  /// canonical state stays correct; this just keeps the UI in sync between
  /// the sale completing and the next inventory refresh. Notifies once if any
  /// item changed.
  void applyDeductions(Map<String, double> deltas) {
    var changed = false;
    for (final e in deltas.entries) {
      final idx = _inventory.indexWhere((it) => it.id == e.key);
      if (idx < 0) continue;
      _inventory[idx].currentStock =
          (_inventory[idx].currentStock - e.value).clamp(0, double.infinity);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Replaces the whole inventory item list (used by AppState's void/refund
  /// flow after a server-side restock re-fetch). Notifies.
  void replaceItems(List<InventoryItem> items) {
    _inventory = items;
    notifyListeners();
  }

  // ───── inventory categories CRUD ─────────────────────

  Future<String?> addInventoryCategory(InventoryCategory c) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (c.name.trim().isEmpty) return 'Category name is required.';
    try {
      final row = await supabase
          .from('inventory_categories')
          .insert({
            'tenant_id': tenantId,
            'name': c.name.trim(),
            'icon_name': c.iconName,
            'sort_order': c.sortOrder,
          })
          .select('*')
          .single();
      _inventoryCategories.add(InventoryCategory.fromRow(row));
      _inventoryCategories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A category named "${c.name}" already exists.';
      }
      return 'Could not add category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateInventoryCategory(InventoryCategory updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Category name is required.';
    try {
      final row = await supabase
          .from('inventory_categories')
          .update({
            'name': updated.name.trim(),
            'icon_name': updated.iconName,
            'sort_order': updated.sortOrder,
          })
          .eq('id', updated.id)
          .select('*')
          .single();
      final fresh = InventoryCategory.fromRow(row);
      final i = _inventoryCategories.indexWhere((c) => c.id == fresh.id);
      if (i >= 0) _inventoryCategories[i] = fresh;
      _inventoryCategories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Items already point at the same id — denormalized `category` text
      // on each item is updated lazily next time the item is saved (or
      // on the next tenant reload). Cheap to refresh names here.
      for (final it in _inventory) {
        if (it.categoryId == fresh.id) it.category = fresh.name;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeInventoryCategory(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('inventory_categories').delete().eq('id', id);
      _inventoryCategories.removeWhere((c) => c.id == id);
      // Items keep their text `category` as a display fallback; the FK is
      // already nulled by the ON DELETE SET NULL clause on the column.
      for (final it in _inventory) {
        if (it.categoryId == id) it.categoryId = null;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── inventory items CRUD ───────────────────────────────

  Future<String?> addInventoryItem(InventoryItem item) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (item.name.trim().isEmpty) return 'Item name is required.';
    try {
      final row = await supabase
          .from('inventory_items')
          .insert(item.toRowPayload(tenantId))
          .select('*')
          .single();
      _inventory.add(InventoryItem.fromRow(row));
      _inventory.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'An inventory item named "${item.name}" already exists.';
      }
      return 'Could not add item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateInventoryItem(InventoryItem updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('inventory_items')
          .update(updated.toRowPayload(tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id);
      final i = _inventory.indexWhere((it) => it.id == updated.id);
      if (i >= 0) _inventory[i] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeInventoryItem(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('inventory_items').delete().eq('id', id);
      _inventory.removeWhere((it) => it.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Server-side atomic stock change (never a client-computed absolute value),
  /// so two devices adjusting the same item can't clobber each other. Updates
  /// the local cache from the authoritative value the DB returns.
  Future<String?> adjustStock(String id, double delta) async {
    final i = _inventory.indexWhere((it) => it.id == id);
    if (i < 0) return 'Item not found.';
    try {
      final newStock = await supabase.rpc('adjust_inventory_stock', params: {
        'p_item_id': id,
        'p_delta': delta,
      });
      _inventory[i].currentStock = (newStock as num).toDouble();
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not adjust stock: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> restock(String id, double qty,
      {double? newCostPerUnit}) async {
    if (qty <= 0) return 'Quantity must be positive.';
    final i = _inventory.indexWhere((it) => it.id == id);
    if (i < 0) return 'Item not found.';
    try {
      final newStock = await supabase.rpc('adjust_inventory_stock', params: {
        'p_item_id': id,
        'p_delta': qty,
        'p_set_restocked': true,
        if (newCostPerUnit != null && newCostPerUnit > 0)
          'p_new_cost_cents': (newCostPerUnit * 100).round(),
      });
      final item = _inventory[i];
      item.currentStock = (newStock as num).toDouble();
      item.lastRestockedAt = DateTime.now();
      if (newCostPerUnit != null && newCostPerUnit > 0) {
        item.costPerUnit = newCostPerUnit;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not restock: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }
}
