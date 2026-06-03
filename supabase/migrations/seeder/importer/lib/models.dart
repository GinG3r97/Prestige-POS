import 'package:meta/meta.dart';

/// Typed shape of one row from the canonical Categories sheet.
@immutable
class CategoryRow {
  const CategoryRow({required this.name, this.iconName, this.sortOrder});
  final String name;
  final String? iconName;
  final int? sortOrder;
}

/// Typed shape of one row from the canonical Inventory sheet. All quantities
/// are stored in `unit` (the base unit — g, ml or pcs) after normalisation.
@immutable
class InventoryRow {
  const InventoryRow({
    required this.name,
    required this.category,
    required this.unit,
    this.unitLabel,
    required this.packSize,
    required this.packPrice,
    this.startingStock = 0,
    this.lowStockThreshold = 0,
    this.supplier,
    this.origin = 'sheet',
  });
  final String name;
  final String category;
  final String unit;
  final String? unitLabel;
  final double packSize;
  final double packPrice;
  final double startingStock;
  final double lowStockThreshold;
  final String? supplier;
  /// 'sheet' = directly from the Inventory sheet. 'book' = expanded from a
  /// Books-sheet row. 'placeholder' = ingredient referenced by a recipe but
  /// missing from Inventory; the importer creates a zero-cost stub so the
  /// recipe still resolves (owner fills the gap later).
  final String origin;

  double get costPerUnit =>
      packSize > 0 ? (packPrice / packSize) : 0;
}

/// Typed shape of one row from the canonical Products sheet.
@immutable
class ProductRow {
  const ProductRow({
    required this.name,
    required this.type,
    required this.category,
    required this.basePrice,
    this.subtitle,
    this.imageUrl,
    this.available = true,
    this.origin = 'sheet',
  });
  final String name;
  /// One of: Drink, Food, Pastry, Book, Retail, Service.
  final String type;
  final String category;
  final double basePrice;
  final String? subtitle;
  final String? imageUrl;
  final bool available;
  /// 'sheet' = direct from Products sheet. 'book' = expanded from Books.
  final String origin;
}

/// Typed shape of one row from the canonical Recipes sheet.
@immutable
class RecipeRow {
  const RecipeRow({
    required this.productName,
    required this.ingredientName,
    required this.quantity,
  });
  final String productName;
  final String ingredientName;
  /// In the inventory item's base unit.
  final double quantity;
}

/// Typed shape of one row from the canonical Books shortcut sheet. Each row
/// is expanded by the writer into one [InventoryRow] + one [ProductRow] +
/// one [RecipeRow] (so the per-book stock auto-deducts on every book sale).
@immutable
class BookRow {
  const BookRow({
    required this.sku,
    required this.title,
    required this.sellingPrice,
    this.costPrice,
    this.startingStock = 0,
    this.category = 'Books',
  });
  final String sku;
  final String title;
  final double sellingPrice;
  final double? costPrice;
  final int startingStock;
  final String category;

  /// 30% of selling price is the standard book margin owners assume when the
  /// supplier cost isn't filled in.
  double get effectiveCostPrice =>
      costPrice ?? (sellingPrice * 0.3);
}

/// Container holding every parsed sheet. Result of running the parser.
class ParsedWorkbook {
  ParsedWorkbook({
    required this.categories,
    required this.inventory,
    required this.products,
    required this.recipes,
    required this.books,
    required this.warnings,
  });
  final List<CategoryRow> categories;
  final List<InventoryRow> inventory;
  final List<ProductRow> products;
  final List<RecipeRow> recipes;
  final List<BookRow> books;
  /// Non-fatal issues collected during parsing — empty headers, unknown
  /// values, etc. Shown in the dry-run summary.
  final List<String> warnings;

  int get totalOps =>
      categories.length +
      inventory.length +
      products.length +
      recipes.length +
      (books.length * 2);
}

/// Result of running validation against a [ParsedWorkbook]. `errors` aborts
/// the apply; `warnings` is informational.
class ValidationResult {
  ValidationResult({required this.errors, required this.warnings});
  final List<String> errors;
  final List<String> warnings;
  bool get ok => errors.isEmpty;
}
