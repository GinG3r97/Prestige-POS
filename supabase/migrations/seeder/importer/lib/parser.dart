import 'dart:io';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'models.dart';
import 'units.dart';

/// Reads a canonical client onboarding xlsx and emits a typed
/// [ParsedWorkbook]. Tolerant of two layouts:
/// - **Pretty layout** (template.xlsx): row 1 is a wrapped instruction
///   note, row 2 is the column headers, data starts at row 3.
/// - **Plain layout** (machine-generated examples / client-saved files):
///   row 1 is the headers, data starts at row 2.
///
/// The parser picks the right offset by looking at row 2's first cell —
/// if it looks like a column name we recognise, we treat row 2 as the
/// header row; otherwise row 1 is the header row.
class WorkbookParser {
  final List<String> _warnings = [];

  ParsedWorkbook parseFile(String path) {
    final bytes = File(path).readAsBytesSync();
    final excel = SpreadsheetDecoder.decodeBytes(bytes);

    final categories = _parseCategories(excel);
    final inventory = _parseInventory(excel);
    final products = _parseProducts(excel);
    final recipes = _parseRecipes(excel);
    final books = _parseBooks(excel);

    return ParsedWorkbook(
      categories: categories,
      inventory: inventory,
      products: products,
      recipes: recipes,
      books: books,
      warnings: List.unmodifiable(_warnings),
    );
  }

  // ─── helpers ──────────────────────────────────────────────────────

  /// Returns the header → column-index map + the data start row (0-indexed).
  /// Returns null if the sheet doesn't exist.
  ({Map<String, int> headers, int dataStart})? _headerLayout(
      SpreadsheetDecoder excel, String sheetName, Set<String> knownKeys) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) return null;
    final rows = sheet.rows;
    if (rows.isEmpty) return (headers: const {}, dataStart: 0);

    // Try row 1 first (machine-generated layout). If at least one cell
    // matches a known column key, accept row 1 as the header row. Otherwise
    // try row 2 (pretty layout with instruction strip at row 1).
    for (final candidateIdx in [0, 1]) {
      if (candidateIdx >= rows.length) continue;
      final candidate = rows[candidateIdx];
      final map = <String, int>{};
      for (var i = 0; i < candidate.length; i++) {
        final raw = candidate[i];
        if (raw == null) continue;
        final key = raw.toString().trim().toLowerCase();
        if (key.isNotEmpty) map[key] = i;
      }
      if (map.keys.any(knownKeys.contains)) {
        return (headers: map, dataStart: candidateIdx + 1);
      }
    }
    return null;
  }

  Iterable<List<dynamic>> _dataRows(
      SpreadsheetDecoder excel, String sheetName, int startIdx) sync* {
    final sheet = excel.tables[sheetName];
    if (sheet == null) return;
    for (var i = startIdx; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c == null || c.toString().trim().isEmpty)) {
        continue;
      }
      yield row;
    }
  }

  String? _str(List<dynamic> row, int? idx) {
    if (idx == null || idx >= row.length) return null;
    final v = row[idx];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? _num(List<dynamic> row, int? idx) {
    final s = _str(row, idx);
    if (s == null) return null;
    return double.tryParse(s);
  }

  int? _int(List<dynamic> row, int? idx) => _num(row, idx)?.toInt();

  bool _boolish(List<dynamic> row, int? idx, {bool fallback = true}) {
    final s = _str(row, idx)?.toLowerCase();
    if (s == null) return fallback;
    if (s == 'yes' || s == 'y' || s == 'true' || s == '1') return true;
    if (s == 'no' || s == 'n' || s == 'false' || s == '0') return false;
    return fallback;
  }

  // ─── sheet parsers ───────────────────────────────────────────────

  List<CategoryRow> _parseCategories(SpreadsheetDecoder excel) {
    final layout = _headerLayout(excel, 'Categories',
        {'name', 'icon_name', 'sort_order'});
    if (layout == null) {
      _warnings.add('Sheet "Categories" not present — categories will be auto-created from referenced names.');
      return const [];
    }
    final headers = layout.headers;
    final out = <CategoryRow>[];
    var ri = layout.dataStart;
    for (final row in _dataRows(excel, 'Categories', layout.dataStart)) {
      ri++;
      final name = _str(row, headers['name']);
      if (name == null) {
        _warnings.add('Categories row $ri has no name — skipped.');
        continue;
      }
      out.add(CategoryRow(
        name: name,
        iconName: _str(row, headers['icon_name']),
        sortOrder: _int(row, headers['sort_order']),
      ));
    }
    return out;
  }

  List<InventoryRow> _parseInventory(SpreadsheetDecoder excel) {
    final layout = _headerLayout(excel, 'Inventory',
        {'name', 'category', 'unit', 'pack_size', 'pack_price'});
    if (layout == null) {
      _warnings.add('Sheet "Inventory" not present — no inventory items will be created.');
      return const [];
    }
    final headers = layout.headers;
    final missing = ['name', 'category', 'unit', 'pack_size', 'pack_price']
        .where((c) => !headers.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      _warnings.add('Inventory sheet missing required column(s): ${missing.join(", ")}.');
      return const [];
    }
    final out = <InventoryRow>[];
    var ri = layout.dataStart;
    for (final row in _dataRows(excel, 'Inventory', layout.dataStart)) {
      ri++;
      final name = _str(row, headers['name']);
      final cat = _str(row, headers['category']);
      final unitRaw = _str(row, headers['unit']);
      final packSize = _num(row, headers['pack_size']);
      final packPrice = _num(row, headers['pack_price']);
      if (name == null || cat == null || unitRaw == null ||
          packSize == null || packPrice == null) {
        _warnings.add('Inventory row $ri "${name ?? "?"}" missing a required field — skipped.');
        continue;
      }
      final norm = normaliseUnit(unitRaw);
      if (norm == null) {
        _warnings.add('Inventory row $ri "$name": unit "$unitRaw" not recognised. Use g, ml or pcs (kg and L also accepted). Skipped.');
        continue;
      }
      out.add(InventoryRow(
        name: name,
        category: cat,
        unit: norm.unit,
        unitLabel: _str(row, headers['unit_label']),
        packSize: packSize * norm.multiplier,
        packPrice: packPrice,
        startingStock: (_num(row, headers['starting_stock']) ?? 0) * norm.multiplier,
        lowStockThreshold: (_num(row, headers['low_stock_threshold']) ?? 0) * norm.multiplier,
        supplier: _str(row, headers['supplier']),
      ));
    }
    return out;
  }

  List<ProductRow> _parseProducts(SpreadsheetDecoder excel) {
    final layout = _headerLayout(excel, 'Products',
        {'name', 'type', 'category', 'base_price'});
    if (layout == null) {
      _warnings.add('Sheet "Products" not present — no products will be created.');
      return const [];
    }
    final headers = layout.headers;
    final missing = ['name', 'type', 'category', 'base_price']
        .where((c) => !headers.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      _warnings.add('Products sheet missing required column(s): ${missing.join(", ")}.');
      return const [];
    }
    final out = <ProductRow>[];
    var ri = layout.dataStart;
    for (final row in _dataRows(excel, 'Products', layout.dataStart)) {
      ri++;
      final name = _str(row, headers['name']);
      final typeRaw = _str(row, headers['type']);
      final cat = _str(row, headers['category']);
      final price = _num(row, headers['base_price']);
      if (name == null || typeRaw == null || cat == null || price == null) {
        _warnings.add('Products row $ri "${name ?? "?"}" missing a required field — skipped.');
        continue;
      }
      final type = canonicaliseProductType(typeRaw);
      if (type == null) {
        _warnings.add('Products row $ri "$name": type "$typeRaw" not recognised. Use Drink, Food, Pastry, Book, Retail or Service. Skipped.');
        continue;
      }
      out.add(ProductRow(
        name: name,
        type: type,
        category: cat,
        basePrice: price,
        subtitle: _str(row, headers['subtitle']),
        imageUrl: _str(row, headers['image_url']),
        available: _boolish(row, headers['available']),
      ));
    }
    return out;
  }

  List<RecipeRow> _parseRecipes(SpreadsheetDecoder excel) {
    final layout = _headerLayout(excel, 'Recipes',
        {'product_name', 'ingredient_name', 'quantity'});
    if (layout == null) return const [];
    final headers = layout.headers;
    final missing = ['product_name', 'ingredient_name', 'quantity']
        .where((c) => !headers.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      _warnings.add('Recipes sheet missing required column(s): ${missing.join(", ")}.');
      return const [];
    }
    final out = <RecipeRow>[];
    var ri = layout.dataStart;
    for (final row in _dataRows(excel, 'Recipes', layout.dataStart)) {
      ri++;
      final pn = _str(row, headers['product_name']);
      final ing = _str(row, headers['ingredient_name']);
      final qty = _num(row, headers['quantity']);
      if (pn == null || ing == null || qty == null) {
        _warnings.add('Recipes row $ri missing a required field — skipped.');
        continue;
      }
      out.add(RecipeRow(productName: pn, ingredientName: ing, quantity: qty));
    }
    return out;
  }

  List<BookRow> _parseBooks(SpreadsheetDecoder excel) {
    final layout = _headerLayout(excel, 'Books',
        {'sku', 'title', 'selling_price'});
    if (layout == null) return const [];
    final headers = layout.headers;
    final missing = ['sku', 'title', 'selling_price']
        .where((c) => !headers.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      _warnings.add('Books sheet missing required column(s): ${missing.join(", ")}.');
      return const [];
    }
    final out = <BookRow>[];
    var ri = layout.dataStart;
    for (final row in _dataRows(excel, 'Books', layout.dataStart)) {
      ri++;
      final sku = _str(row, headers['sku']);
      final title = _str(row, headers['title']);
      final price = _num(row, headers['selling_price']);
      if (sku == null || title == null || price == null) {
        _warnings.add('Books row $ri missing a required field — skipped.');
        continue;
      }
      out.add(BookRow(
        sku: sku,
        title: title,
        sellingPrice: price,
        costPrice: _num(row, headers['cost_price']),
        startingStock: _int(row, headers['starting_stock']) ?? 0,
        category: _str(row, headers['category']) ?? 'Books',
      ));
    }
    return out;
  }
}
