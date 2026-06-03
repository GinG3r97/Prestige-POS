import 'package:supabase/supabase.dart';

import 'models.dart';

/// Writes the parsed + validated workbook into a tenant. Idempotent on
/// `lower(name)`, so re-running after fixing a typo just patches that
/// row instead of duplicating.
class TenantSeeder {
  TenantSeeder({
    required this.client,
    required this.tenantId,
  });
  final SupabaseClient client;
  final String tenantId;

  Future<SeedReport> run(ParsedWorkbook wb) async {
    final report = SeedReport();

    // 1. Resolve product type ids (Drink/Food/Pastry/Book/Retail/Service)
    final typeIds = await _loadProductTypeIds();

    // 2. Categories
    final categoryIds = <String, String>{}; // lowercased name → id
    final allCategories = <CategoryRow>[
      ...wb.categories,
      // Auto-declare any product category that wasn't in the Categories sheet
      ...wb.products
          .map((p) => p.category.toLowerCase())
          .toSet()
          .difference(wb.categories.map((c) => c.name.toLowerCase()).toSet())
          .map((name) => CategoryRow(name: _titleCase(name))),
      // Auto-declare Book category if Books sheet is non-empty
      if (wb.books.isNotEmpty &&
          !wb.categories
              .any((c) => c.name.toLowerCase() == 'books'))
        const CategoryRow(name: 'Books', iconName: 'menu_book_outlined'),
    ];
    for (final c in allCategories) {
      final id = await _upsertCategory(c);
      categoryIds[c.name.toLowerCase()] = id;
      report.categories++;
    }

    // 3. Inventory items (explicit + book-expanded + placeholders)
    final inventoryIds = <String, String>{}; // lowercased name → id
    for (final r in wb.inventory) {
      final id = await _upsertInventory(r);
      inventoryIds[r.name.toLowerCase()] = id;
      report.inventoryItems++;
    }
    // Placeholders for recipe ingredients missing from inventory
    final invNames = wb.inventory.map((r) => r.name.toLowerCase()).toSet();
    final needsPlaceholder = <String>{};
    for (final r in wb.recipes) {
      if (!invNames.contains(r.ingredientName.toLowerCase())) {
        needsPlaceholder.add(r.ingredientName);
      }
    }
    for (final name in needsPlaceholder) {
      final row = InventoryRow(
        name: name,
        category: 'Placeholder',
        unit: 'g',
        packSize: 1,
        packPrice: 0,
        origin: 'placeholder',
      );
      final id = await _upsertInventory(row);
      inventoryIds[name.toLowerCase()] = id;
      report.placeholders++;
    }
    // Books → expanded inventory rows
    for (final b in wb.books) {
      final inv = InventoryRow(
        name: b.title,
        category: b.category,
        unit: 'pcs',
        packSize: 1,
        packPrice: b.effectiveCostPrice,
        startingStock: b.startingStock.toDouble(),
        lowStockThreshold: 0,
        origin: 'book',
      );
      final id = await _upsertInventory(inv, sku: b.sku);
      inventoryIds[b.title.toLowerCase()] = id;
      report.inventoryItems++;
    }

    // 4. Products + their resolved recipe lines
    // Group recipe rows by product name first so each product save carries
    // its full recipe in one update.
    final recipesByProduct = <String, List<RecipeRow>>{};
    for (final r in wb.recipes) {
      recipesByProduct.putIfAbsent(r.productName.toLowerCase(), () => []).add(r);
    }
    for (final p in wb.products) {
      final typeId = typeIds[p.type];
      if (typeId == null) {
        report.errors.add('Product "${p.name}": no DB product_type row matches "${p.type}". Skipped.');
        continue;
      }
      final catId = categoryIds[p.category.toLowerCase()];
      if (catId == null) {
        report.errors.add('Product "${p.name}": category "${p.category}" not resolved. Skipped.');
        continue;
      }
      final recipeJson = (recipesByProduct[p.name.toLowerCase()] ?? const [])
          .map((r) {
            final invId = inventoryIds[r.ingredientName.toLowerCase()];
            if (invId == null) return null;
            return {
              'inventory_item_id': invId,
              'quantity': r.quantity,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      await _upsertProduct(
        row: p,
        typeId: typeId,
        categoryId: catId,
        recipe: recipeJson,
      );
      report.products++;
      report.recipeLines += recipeJson.length;
    }

    // 5. Books → expanded products + recipe[1pc of self]
    for (final b in wb.books) {
      final typeId = typeIds['Book'];
      if (typeId == null) {
        report.errors.add('Book "${b.title}": no DB product_type row for "Book".');
        continue;
      }
      final catId = categoryIds[b.category.toLowerCase()];
      if (catId == null) {
        report.errors.add('Book "${b.title}": category "${b.category}" not resolved.');
        continue;
      }
      final invId = inventoryIds[b.title.toLowerCase()];
      final pRow = ProductRow(
        name: b.title,
        type: 'Book',
        category: b.category,
        basePrice: b.sellingPrice,
        subtitle: 'SKU ${b.sku}',
        origin: 'book',
      );
      await _upsertProduct(
        row: pRow,
        typeId: typeId,
        categoryId: catId,
        recipe: invId == null
            ? const []
            : [
                {'inventory_item_id': invId, 'quantity': 1.0},
              ],
      );
      report.products++;
      report.recipeLines += invId == null ? 0 : 1;
    }

    return report;
  }

  // ─── helpers ──────────────────────────────────────────────────────

  Future<Map<String, String>> _loadProductTypeIds() async {
    final rows = await client
        .from('product_types')
        .select('id, name')
        .eq('tenant_id', tenantId);
    final map = <String, String>{};
    for (final r in rows) {
      map[(r['name'] as String)] = r['id'] as String;
    }
    return map;
  }

  Future<String> _upsertCategory(CategoryRow r) async {
    final existing = await client
        .from('categories')
        .select('id')
        .eq('tenant_id', tenantId)
        .ilike('name', r.name)
        .maybeSingle();
    final payload = {
      'tenant_id': tenantId,
      'name': r.name,
      'icon_name': r.iconName,
      if (r.sortOrder != null) 'sort_order': r.sortOrder,
    };
    if (existing != null) {
      await client
          .from('categories')
          .update(payload)
          .eq('id', existing['id'] as String);
      return existing['id'] as String;
    }
    final inserted = await client
        .from('categories')
        .insert(payload)
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  Future<String> _upsertInventory(InventoryRow r, {String? sku}) async {
    final existing = await client
        .from('inventory_items')
        .select('id')
        .eq('tenant_id', tenantId)
        .ilike('name', r.name)
        .maybeSingle();
    final payload = {
      'tenant_id': tenantId,
      'name': r.name,
      'category': r.category,
      'unit': r.unit,
      'unit_label': r.unitLabel,
      'current_stock': r.startingStock,
      'low_stock_threshold': r.lowStockThreshold,
      'cost_per_unit_cents': (r.costPerUnit * 100).round(),
      'supplier': r.supplier ?? '',
      if (sku != null) 'sku': sku,
    };
    if (existing != null) {
      await client
          .from('inventory_items')
          .update(payload)
          .eq('id', existing['id'] as String);
      return existing['id'] as String;
    }
    final inserted = await client
        .from('inventory_items')
        .insert(payload)
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  Future<String> _upsertProduct({
    required ProductRow row,
    required String typeId,
    required String categoryId,
    required List<Map<String, dynamic>> recipe,
  }) async {
    final existing = await client
        .from('products')
        .select('id')
        .eq('tenant_id', tenantId)
        .ilike('name', row.name)
        .maybeSingle();
    final payload = {
      'tenant_id': tenantId,
      'name': row.name,
      'type_id': typeId,
      'category_id': categoryId,
      'base_price_cents': (row.basePrice * 100).round(),
      'subtitle': row.subtitle ?? '',
      'image_url': row.imageUrl,
      'available': row.available,
      'recipe': recipe,
    };
    if (existing != null) {
      await client
          .from('products')
          .update(payload)
          .eq('id', existing['id'] as String);
      return existing['id'] as String;
    }
    final inserted = await client
        .from('products')
        .insert(payload)
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }
}

class SeedReport {
  int categories = 0;
  int inventoryItems = 0;
  int placeholders = 0;
  int products = 0;
  int recipeLines = 0;
  final List<String> errors = [];

  bool get ok => errors.isEmpty;
}
