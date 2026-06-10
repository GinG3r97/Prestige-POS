import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../data/supabase_client.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;

const _uuid = Uuid();

/// Owns the Catalog domain (product types, sub-type categories, master
/// modifier groups, add-ons, and products), extracted from the monolithic
/// [AppState] so that the rest of the app watching AppState no longer rebuilds
/// when a catalog row changes. Catalog-data consumers (Sell, Products, cart,
/// product detail, Maintenance catalog sections, Reports, Orders) watch this
/// store directly via its own provider.
///
/// AppState owns a single instance ([AppState.catalog]) and drives its
/// lifecycle via [hydrate] (on tenant restore — including the per-product
/// runtime modifier-group join) and [reset] (on sign-out / tenant switch). The
/// product-type SEED used during onboarding is exposed via
/// [seedDefaultProductTypes].
///
/// The Supabase calls, sorting, and notify timing are identical to what
/// AppState used to do inline. The money-path coordinator methods
/// (expandRecipe / canSell / projectedDeductions / checkout) STAY on AppState
/// and reach catalog data through the thin delegates AppState keeps on itself.
class CatalogStore extends ChangeNotifier {
  /// The active tenant DB id, set by [hydrate]. All mutations are scoped to
  /// this tenant. `null` means no store is selected (signed out / no tenant).
  /// Mirrors what AppState called `_currentTenantDbId`.
  String? _tenantId;

  // ───── categories (sub-types) ─────

  /// Tenant-owned categories from `public.categories`, populated on session
  /// restore and kept in sync with DB writes.
  List<cat.Category> _categories = [];
  List<cat.Category> get categories => List.unmodifiable(_categories);

  /// Find a category (sub-type) by id. Null-safe — returns null for a missing
  /// or null id (e.g. a product whose category was deleted).
  cat.Category? categoryById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Sub-types (categories) under a given product type, sorted by sort order.
  /// Pass null to get unassigned sub-types (the "Other" bucket).
  List<cat.Category> categoriesForType(String? typeId) =>
      (_categories.where((c) => c.typeId == typeId).toList())
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The product type a product effectively belongs to for the two-level Sell
  /// browser. Prefers the product's own `typeId`; falls back to its category's
  /// `typeId`; null means "Other" (no resolvable type).
  String? effectiveTypeId(CafeItem p) =>
      p.typeId ?? categoryById(p.categoryId)?.typeId;

  // ───── master modifier groups ─────

  List<MasterModifierGroup> _modifierGroups = [];
  List<MasterModifierGroup> get modifierGroups =>
      List.unmodifiable(_modifierGroups);

  // ───── add-ons ─────

  List<AddOn> _addOns = [];
  List<AddOn> get addOns => List.unmodifiable(_addOns);

  // ───── product types ─────

  List<ProductType> _productTypes = [];
  List<ProductType> get productTypes => List.unmodifiable(_productTypes);

  ProductType? productTypeById(String? id) {
    if (id == null) return null;
    for (final t in _productTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ───── products ─────

  List<CafeItem> _products = [];
  List<CafeItem> get products => List.unmodifiable(_products);

  CafeItem? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ───── lifecycle ─────

  /// Loads categories, master modifier groups, product types, products
  /// (including the per-product runtime modifier-group join) and add-ons for
  /// [tenantId] from Supabase, then notifies. Called by AppState during tenant
  /// hydration. Categories / modifier groups / product types are independent
  /// of each other, so they run CONCURRENTLY (same parallelism AppState used
  /// inline); products fetch AFTER that batch because their post-processing
  /// joins against the categories + modifier groups loaded here.
  Future<void> hydrate(String tenantId) async {
    _tenantId = tenantId;
    final tid = tenantId as Object;
    await Future.wait<void>([
      () async {
        final categoriesRes = await supabase
            .from('categories')
            .select(
                'id, name, emoji, icon_name, sort_order, type_id, is_system, separate_sales')
            .eq('tenant_id', tid)
            .order('sort_order');
        _categories = (categoriesRes as List)
            .map((r) => cat.Category.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
      () async {
        final mgRows = await supabase
            .from('modifier_groups')
            .select(
                'id, name, emoji, icon_name, required, default_index, sort_order, is_system, '
                'modifier_options(id, name, price_delta_cents, sort_order)')
            .eq('tenant_id', tid)
            .order('sort_order');
        _modifierGroups = (mgRows as List).map((r) {
          final row = r as Map<String, dynamic>;
          // Sort the raw rows by sort_order first (O(n log n)), then map.
          final optsRaw = [...(row['modifier_options'] as List? ?? const [])]
            ..sort((a, b) => (((a as Map)['sort_order'] as int?) ?? 0)
                .compareTo(((b as Map)['sort_order'] as int?) ?? 0));
          final opts = optsRaw
              .map((o) => MasterOption.fromRow(o as Map<String, dynamic>))
              .toList();
          return MasterModifierGroup.fromRow(row, options: opts);
        }).toList();
      }(),
      () async {
        final typeRows = await supabase
            .from('product_types')
            .select('*')
            .eq('tenant_id', tid)
            .order('sort_order');
        _productTypes = (typeRows as List)
            .map((r) => ProductType.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
    ]);

    // Products — joined with type + category for denormalized names.
    final prodRows = await supabase
        .from('products')
        .select('*, type:product_types(id, name), '
            'category:categories(id, name)')
        .eq('tenant_id', tid)
        .order('sort_order');
    _products = (prodRows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return CafeItem.fromRow(
        row,
        typeRow: row['type'] as Map<String, dynamic>?,
        categoryRow: row['category'] as Map<String, dynamic>?,
      );
    }).toList();

    // Hydrate runtime `modifierGroups` on each product from the master list so
    // the Sell view + product detail sheet can render Size / Temperature /
    // Strength pickers without rewriting their data sources. DB stores only
    // the ids; this is the in-memory join.
    final categoriesById = {for (final c in _categories) c.id: c};
    for (final p in _products) {
      p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
      // Fall back to the category's picked icon when the product has none — so
      // every product shows a themed outlined icon consistently across
      // Sell / Orders / Products / cart.
      if ((p.iconName == null || p.iconName!.isEmpty) &&
          p.categoryId != null) {
        final c = categoriesById[p.categoryId];
        if (c != null && c.iconName != null && c.iconName!.isNotEmpty) {
          p.iconName = c.iconName;
        }
      }
    }

    // Add-ons — tenant-owned extras with per-category applicability.
    final addOnRows = await supabase
        .from('add_ons')
        .select('*')
        .eq('tenant_id', tid)
        .order('sort_order');
    _addOns = (addOnRows as List)
        .map((r) => AddOn.fromRow(r as Map<String, dynamic>))
        .toList();

    notifyListeners();
  }

  /// Seeds the categories list straight from the rows inserted during
  /// onboarding (before a full [hydrate] runs), so the freshly-created store
  /// shows its starter sub-types in Sell immediately. Mirrors the old inline
  /// `_categories = fetchedCategories..sort(...)` assignment in
  /// AppState.completeOnboarding.
  void seedCategoriesFromOnboarding(
      String tenantId, List<cat.Category> categories) {
    _tenantId = tenantId;
    _categories = categories
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
  }

  /// Clears the active-tenant catalog view (sign-out / tenant switch). Mirrors
  /// the old AppState reset which wiped these lists.
  void reset() {
    _tenantId = null;
    _categories = [];
    _modifierGroups = [];
    _productTypes = [];
    _products = [];
    _addOns = [];
    notifyListeners();
  }

  // ───── Categories CRUD (Maintenance) ─────────────────────

  /// Creates a new category on the active tenant. Returns null on success, or a
  /// user-safe error string on failure.
  Future<String?> addCategory({
    required String name,
    required String emoji,
    String? iconName,
    int sortOrder = 0,
    String? typeId,
    bool separateSales = false,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (name.trim().isEmpty) return 'Category name is required.';
    try {
      final inserted = await supabase
          .from('categories')
          .insert({
            'tenant_id': tenantId,
            'name': name.trim(),
            'emoji': emoji.trim(),
            'icon_name': iconName,
            'sort_order': sortOrder,
            'type_id': typeId,
            'separate_sales': separateSales,
          })
          .select('id, name, emoji, icon_name, sort_order, type_id, '
              'is_system, separate_sales')
          .single();
      _categories.add(cat.Category.fromRow(inserted));
      _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // 23505 = unique violation (duplicate name for this tenant).
      if (e.code == '23505') {
        return 'You already have a category named "$name".';
      }
      return 'Could not add category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateCategory(cat.Category updated) async {
    if (_tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Category name is required.';
    try {
      await supabase.from('categories').update({
        'name': updated.name.trim(),
        'emoji': updated.emoji.trim(),
        'icon_name': updated.iconName,
        'sort_order': updated.sortOrder,
        'type_id': updated.typeId,
        'separate_sales': updated.separateSales,
      }).eq('id', updated.id);
      final i = _categories.indexWhere((c) => c.id == updated.id);
      if (i >= 0) {
        _categories[i] = updated;
        _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a category named "${updated.name}".';
      }
      return 'Could not update category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeCategory(String categoryId) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('categories').delete().eq('id', categoryId);
      _categories.removeWhere((c) => c.id == categoryId);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // 23503 = foreign-key violation (a sellable still references this category).
      if (e.code == '23503') {
        return 'Move or delete the items in this category first.';
      }
      return 'Could not delete category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Master modifier groups CRUD (Maintenance) ─────

  /// Creates a new modifier group + its options on the active tenant.
  /// Returns null on success, or a user-safe error message.
  Future<String?> addModifierGroup(MasterModifierGroup g) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (g.name.trim().isEmpty) return 'Group name is required.';
    try {
      // Insert the group, then its options (the group_id FK is set after
      // the group's row is returned with its DB-assigned uuid).
      final groupRow = await supabase
          .from('modifier_groups')
          .insert({
            'tenant_id': tenantId,
            'name': g.name.trim(),
            'emoji': g.emoji.trim(),
            'icon_name': g.iconName,
            'required': g.required,
            'default_index': g.defaultIndex,
            'sort_order': g.sortOrder,
          })
          .select(
              'id, name, emoji, icon_name, required, default_index, sort_order, is_system')
          .single();
      final groupId = groupRow['id'] as String;

      List<MasterOption> insertedOptions = [];
      if (g.options.isNotEmpty) {
        final payload = <Map<String, dynamic>>[];
        for (var i = 0; i < g.options.length; i++) {
          payload.add({
            'group_id': groupId,
            'name': g.options[i].name.trim(),
            'price_delta_cents': g.options[i].priceDelta.centavos,
            'sort_order': i,
          });
        }
        final optRows = await supabase
            .from('modifier_options')
            .insert(payload)
            .select('id, name, price_delta_cents, sort_order');
        insertedOptions = (optRows as List)
            .map((r) => MasterOption.fromRow(r as Map<String, dynamic>))
            .toList()
          ..sort((a, b) {
            // Maintain original order by matching back to payload index.
            final ai = g.options.indexWhere((o) => o.name.trim() == a.name);
            final bi = g.options.indexWhere((o) => o.name.trim() == b.name);
            return ai.compareTo(bi);
          });
      }

      _modifierGroups
          .add(MasterModifierGroup.fromRow(groupRow, options: insertedOptions));
      _modifierGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a group named "${g.name}".';
      }
      return 'Could not add group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Updates a modifier group + replaces its options. Simplest correct
  /// strategy: delete-and-reinsert options inside one logical step; the FK
  /// cascade plus the unique(group_id, name) constraint keep us safe.
  Future<String?> updateModifierGroup(MasterModifierGroup updated) async {
    if (_tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Group name is required.';
    try {
      await supabase.from('modifier_groups').update({
        'name': updated.name.trim(),
        'emoji': updated.emoji.trim(),
        'icon_name': updated.iconName,
        'required': updated.required,
        'default_index': updated.defaultIndex,
        'sort_order': updated.sortOrder,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);

      await supabase.from('modifier_options')
          .delete()
          .eq('group_id', updated.id);

      List<MasterOption> insertedOptions = [];
      if (updated.options.isNotEmpty) {
        final payload = <Map<String, dynamic>>[];
        for (var i = 0; i < updated.options.length; i++) {
          payload.add({
            'group_id': updated.id,
            'name': updated.options[i].name.trim(),
            'price_delta_cents': updated.options[i].priceDelta.centavos,
            'sort_order': i,
          });
        }
        final optRows = await supabase
            .from('modifier_options')
            .insert(payload)
            .select('id, name, price_delta_cents, sort_order');
        insertedOptions = (optRows as List)
            .map((r) => MasterOption.fromRow(r as Map<String, dynamic>))
            .toList();
      }

      final i = _modifierGroups.indexWhere((g) => g.id == updated.id);
      if (i >= 0) {
        _modifierGroups[i] = MasterModifierGroup(
          id: updated.id,
          name: updated.name.trim(),
          emoji: updated.emoji.trim(),
          iconName: updated.iconName,
          required: updated.required,
          defaultIndex: updated.defaultIndex,
          sortOrder: updated.sortOrder,
          options: insertedOptions,
        );
        _modifierGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      // Re-hydrate every product that opted in so cart.unitPrice sees the
      // freshly-edited priceDelta + recipe adjustments. Without this the
      // master cache is updated but products keep the stale runtime copy
      // from initial load, so "Medium = +₱20" never reaches the cart.
      for (final p in _products) {
        if (p.modifierGroupIds.contains(updated.id)) {
          p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a group named "${updated.name}".';
      }
      return 'Could not update group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeModifierGroup(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('modifier_groups').delete().eq('id', id);
      _modifierGroups.removeWhere((g) => g.id == id);
      // Drop the deleted group from any product that opted in and refresh
      // their runtime modifierGroups list. Without this the Sell view
      // would render a zombie picker for a group that no longer exists.
      for (final p in _products) {
        if (p.modifierGroupIds.contains(id)) {
          p.modifierGroupIds = p.modifierGroupIds
              .where((mid) => mid != id)
              .toList();
          p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── add-ons CRUD ─────────────────────────────────

  Future<String?> addAddOn(AddOn addOn) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (addOn.name.trim().isEmpty) return 'Add-on name is required.';
    try {
      final row = await supabase
          .from('add_ons')
          .insert(addOn.toRowPayload(tenantId))
          .select('*')
          .single();
      _addOns.add(AddOn.fromRow(row));
      _addOns.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'An add-on named "${addOn.name}" already exists.';
      }
      return 'Could not add: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateAddOn(AddOn updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Add-on name is required.';
    try {
      await supabase
          .from('add_ons')
          .update(updated.toRowPayload(tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id);
      final i = _addOns.indexWhere((a) => a.id == updated.id);
      if (i >= 0) _addOns[i] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeAddOn(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('add_ons').delete().eq('id', id);
      _addOns.removeWhere((a) => a.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── products CRUD ────────────────────────────────

  Future<String?> addProduct(CafeItem product) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (product.name.trim().isEmpty) return 'Product name is required.';
    try {
      final row = await supabase
          .from('products')
          .insert(productRowPayload(product, tenantId))
          .select('*, type:product_types(id, name), '
              'category:categories(id, name)')
          .single();
      final saved = CafeItem.fromRow(row,
          typeRow: row['type'] as Map<String, dynamic>?,
          categoryRow: row['category'] as Map<String, dynamic>?);
      saved.modifierGroups =
          _runtimeModifierGroups(saved.modifierGroupIds);
      _products.add(saved);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not add product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateProduct(CafeItem updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Product name is required.';
    try {
      final row = await supabase
          .from('products')
          .update(productRowPayload(updated, tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id)
          .select('*, type:product_types(id, name), '
              'category:categories(id, name)')
          .single();
      final saved = CafeItem.fromRow(row,
          typeRow: row['type'] as Map<String, dynamic>?,
          categoryRow: row['category'] as Map<String, dynamic>?);
      saved.modifierGroups =
          _runtimeModifierGroups(saved.modifierGroupIds);
      final i = _products.indexWhere((p) => p.id == saved.id);
      if (i >= 0) _products[i] = saved;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeProduct(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('products').delete().eq('id', id);
      _products.removeWhere((p) => p.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Uploads pre-compressed JPEG bytes to the `product-images` Storage bucket
  /// and returns the public URL. The object path is scoped under the current
  /// tenant id so the RLS policies accept the write. Throws on network failure
  /// so the caller can surface a toast and abort the product save.
  Future<String> uploadProductImage(Uint8List jpegBytes) async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      throw StateError('No store selected.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$tenantId/$ts-${_uuid.v4()}.jpg';
    await supabase.storage.from('product-images').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const sb.FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: false,
          ),
        );
    return supabase.storage.from('product-images').getPublicUrl(path);
  }

  /// Toggles inventory tracking for a single product. Optimistic with
  /// rollback so the switch feels instant.
  Future<String?> setProductTrackInventory(
      CafeItem product, bool value) async {
    final prev = product.trackInventory;
    product.trackInventory = value;
    notifyListeners();
    try {
      final res = await supabase
          .from('products')
          .update({
            'track_inventory': value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', product.id)
          .select('id');
      if ((res as List).isEmpty) {
        product.trackInventory = prev;
        notifyListeners();
        return 'Could not save. Please try again.';
      }
      return null;
    } catch (_) {
      product.trackInventory = prev;
      notifyListeners();
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── product types CRUD (Maintenance → Product types) ───────────

  /// Seeds the default product types for a freshly created tenant and returns
  /// a lowercased name -> id map so onboarding can link the seeded categories
  /// (sub-types) to their parent type. Idempotent via unique(tenant_id, name):
  /// on a duplicate re-run it re-selects the existing rows so the map is always
  /// populated. Returns an empty map on hard failure (callers must tolerate it
  /// — categories simply seed with a null type_id → "Other").
  Future<Map<String, String>> seedDefaultProductTypes(String tenantId) async {
    // Three behavior buckets is all that's needed — types only control
    // whether an item has size/temp options and whether it deducts stock.
    // Menu grouping (Coffee, Tea, Books, Food…) is handled by sub-types.
    final rows = [
      {
        'tenant_id': tenantId,
        'name': 'Drinks',
        'icon_name': 'local_cafe_outlined',
        // Drinks have Size / Temperature / Strength options + add-ons.
        'supports_modifiers': true,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 10,
      },
      {
        'tenant_id': tenantId,
        'name': 'Foods',
        'icon_name': 'restaurant_outlined',
        // Rung up flat (no size/temp); still deducts recipe ingredients.
        'supports_modifiers': false,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 20,
      },
      {
        'tenant_id': tenantId,
        'name': 'Pastries',
        'icon_name': 'bakery_dining_outlined',
        'supports_modifiers': false,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 30,
      },
    ];
    try {
      final inserted = await supabase
          .from('product_types')
          .insert(rows)
          .select('id, name');
      return _typeIdMap(inserted);
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        // Already seeded — re-fetch the existing rows so the map is populated.
        try {
          final existing = await supabase
              .from('product_types')
              .select('id, name')
              .eq('tenant_id', tenantId);
          return _typeIdMap(existing);
        } catch (_) {
          return {};
        }
      }
      if (kDebugMode) {
        debugPrint('Seed default product types failed: ${e.message}');
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Builds a lowercased product-type name -> id map from PostgREST rows.
  Map<String, String> _typeIdMap(dynamic rows) {
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final name = (m['name'] as String?)?.toLowerCase();
      final id = m['id'] as String?;
      if (name != null && id != null) map[name] = id;
    }
    return map;
  }

  Future<String?> addProductType(ProductType t) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (t.name.trim().isEmpty) return 'Type name is required.';
    try {
      final row = await supabase.from('product_types').insert({
        'tenant_id': tenantId,
        'name': t.name.trim(),
        'icon_name': t.iconName,
        'supports_modifiers': t.supportsModifiers,
        'deducts_stock': t.deductsStock,
        'is_system': false,
        'sort_order': t.sortOrder,
        'separate_sales': t.separateSales,
      }).select('*').single();
      _productTypes.add(ProductType.fromRow(row));
      _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A type named "${t.name}" already exists.';
      }
      return 'Could not add type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateProductType(ProductType updated) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('product_types').update({
        'name': updated.name.trim(),
        'icon_name': updated.iconName,
        'supports_modifiers': updated.supportsModifiers,
        'deducts_stock': updated.deductsStock,
        'sort_order': updated.sortOrder,
        'separate_sales': updated.separateSales,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);
      final i = _productTypes.indexWhere((t) => t.id == updated.id);
      if (i >= 0) _productTypes[i] = updated;
      // Keep the list ordered by sort_order (matches updateCategory) so a
      // re-icon/rename that changes order reflects immediately.
      _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Refresh denormalized typeName on any products using this type.
      for (final p in _products) {
        if (p.typeId == updated.id) p.typeName = updated.name.trim();
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A type named "${updated.name}" already exists.';
      }
      return 'Could not update type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeProductType(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('product_types').delete().eq('id', id);
      _productTypes.removeWhere((x) => x.id == id);
      // Products lose their typeId on cascade SET NULL.
      for (final p in _products) {
        if (p.typeId == id) {
          p.typeId = null;
          p.typeName = '';
        }
      }
      // Sub-types (categories) under this type also lose their link (DB SET
      // NULL) — mirror it in memory so the Sell tree doesn't point at a dead
      // type until the next reload. They fall into the "Other" bucket.
      for (final c in _categories) {
        if (c.typeId == id) c.typeId = null;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Drag-to-reorder (Sell "arrange mode") ──────────────────────────
  // Each reassigns sort_order to (index+1)*10 over the given ordering. Memory
  // updates + notifyListeners happen SYNCHRONOUSLY (so the dropped item doesn't
  // snap back), then the rows are written to Supabase. Spacing stays in tens so
  // single inserts elsewhere don't force a renumber.

  /// Persist a new ordering of the product types. Returns null on success or a
  /// user-safe error string if the DB write failed.
  Future<String?> reorderProductTypes(List<ProductType> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders(
        'product_types', ordered, (t) => t.id, (t) => t.sortOrder);
  }

  /// Persist a new ordering of the sub-types within a single product type.
  Future<String?> reorderCategories(List<cat.Category> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders(
        'categories', ordered, (c) => c.id, (c) => c.sortOrder);
  }

  /// Persist a new ordering of the products in the currently-shown subset.
  Future<String?> reorderProducts(List<CafeItem> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _products.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders('products', ordered, (p) => p.id, (p) => p.sortOrder);
  }

  /// Writes each row's sort_order. Returns null on success, or the first
  /// error encountered (and how many rows it managed to save).
  Future<String?> _writeSortOrders<T>(String table, List<T> ordered,
      String Function(T) idOf, int Function(T) sortOf) async {
    var saved = 0;
    for (final item in ordered) {
      try {
        // `.select()` forces the round-trip AND returns the affected rows, so a
        // silent 0-row update (e.g. an RLS/permission block) surfaces as an
        // error instead of looking like it saved and then reverting on reload.
        final res = await supabase
            .from(table)
            .update({'sort_order': sortOf(item)})
            .eq('id', idOf(item))
            .select('id');
        if ((res as List).isEmpty) {
          return 'Order not saved — the server rejected the update for "$table" '
              '(saved $saved of ${ordered.length}). This is usually a '
              'permissions issue.';
        }
        saved++;
      } catch (e) {
        if (kDebugMode) debugPrint('Reorder ($table) row failed: $e');
        return 'Saved $saved of ${ordered.length}. $e';
      }
    }
    return null;
  }

  /// Converts a product's [modifierGroupIds] (DB FKs to master groups)
  /// into the runtime [ModifierGroup] shape the Sell / cart code reads.
  /// Skips ids that don't resolve so a deleted master group doesn't crash
  /// the Sell view.
  List<ModifierGroup> _runtimeModifierGroups(List<String> ids) {
    final out = <ModifierGroup>[];
    for (final id in ids) {
      final master = _modifierGroups.where((m) => m.id == id).firstOrNull;
      if (master == null) continue;
      out.add(ModifierGroup(
        id: master.id,
        name: master.name,
        required: master.required,
        defaultIndex: master.defaultIndex,
        options: master.options
            .map((o) => ModifierOption(
                  id: o.id,
                  name: o.name,
                  priceDelta: o.priceDelta,
                ))
            .toList(),
      ));
    }
    return out;
  }
}
