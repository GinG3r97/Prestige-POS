import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Measurement unit for an inventory item.
enum StockUnit {
  grams,
  kilograms,
  milliliters,
  liters,
  pieces,
  packs,
}

extension StockUnitX on StockUnit {
  /// Short symbol shown in lists ("g", "ml", "pcs").
  String get symbol => switch (this) {
        StockUnit.grams => 'g',
        StockUnit.kilograms => 'kg',
        StockUnit.milliliters => 'ml',
        StockUnit.liters => 'L',
        StockUnit.pieces => 'pcs',
        StockUnit.packs => 'pack',
      };

  /// Canonical string written to `public.inventory_items.unit`. Matches
  /// [symbol] today; kept as a dedicated getter so we can re-spell later
  /// without touching the symbol-display sites.
  String get dbValue => symbol;

  static StockUnit fromDb(String? v) => switch (v) {
        'kg' => StockUnit.kilograms,
        'ml' => StockUnit.milliliters,
        'L' => StockUnit.liters,
        'g' => StockUnit.grams,
        'pack' => StockUnit.packs,
        _ => StockUnit.pieces,
      };

  String get label => switch (this) {
        StockUnit.grams => 'Grams (g)',
        StockUnit.kilograms => 'Kilograms (kg)',
        StockUnit.milliliters => 'Milliliters (ml)',
        StockUnit.liters => 'Liters (L)',
        StockUnit.pieces => 'Pieces',
        StockUnit.packs => 'Packs',
      };

  /// Recipe-side unit category (mass, volume, count). Used to validate that a
  /// recipe quantity in (e.g.) grams can deduct from a stock kept in kg.
  StockUnitFamily get family => switch (this) {
        StockUnit.grams || StockUnit.kilograms => StockUnitFamily.mass,
        StockUnit.milliliters || StockUnit.liters => StockUnitFamily.volume,
        StockUnit.pieces || StockUnit.packs => StockUnitFamily.count,
      };

  /// Returns the multiplier to convert *this* unit to its base
  /// (g for mass, ml for volume, pcs for count). Used so the system can
  /// accept "10g" recipe ingredients deducting from "1kg" stock.
  double get toBase => switch (this) {
        StockUnit.grams => 1,
        StockUnit.kilograms => 1000,
        StockUnit.milliliters => 1,
        StockUnit.liters => 1000,
        StockUnit.pieces => 1,
        StockUnit.packs => 1, // packs treated as count
      };
}

enum StockUnitFamily { mass, volume, count }

/// Reason logged when adjusting stock manually outside of a sale.
enum StockTakeReason { recount, waste, spillage, theft, transfer, other }

extension StockTakeReasonX on StockTakeReason {
  String get label => switch (this) {
        StockTakeReason.recount => 'Recount',
        StockTakeReason.waste => 'Waste / Expired',
        StockTakeReason.spillage => 'Spillage',
        StockTakeReason.theft => 'Loss / Theft',
        StockTakeReason.transfer => 'Transfer to branch',
        StockTakeReason.other => 'Other',
      };
}

/// Tenant-owned inventory category. Mirrors a row in
/// `public.inventory_categories`. Owners create these in
/// Maintenance → Inventory categories; items reference one via
/// [InventoryItem.categoryId] (the canonical link).
class InventoryCategory {
  final String id;
  String name;
  /// Curated Material-icon key (matches the picker used elsewhere).
  String? iconName;
  int sortOrder;
  /// True for rows seeded by the tenant bootstrap. Maintenance shows a
  /// BUILT-IN badge but doesn't block edit / remove.
  final bool isSystem;

  InventoryCategory({
    required this.id,
    required this.name,
    this.iconName,
    this.sortOrder = 0,
    this.isSystem = false,
  });

  factory InventoryCategory.fromRow(Map<String, dynamic> row) =>
      InventoryCategory(
        id: row['id'] as String,
        name: row['name'] as String,
        iconName: row['icon_name'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
        isSystem: (row['is_system'] as bool?) ?? false,
      );
}

class InventoryItem {
  final String id;
  String name;
  String sku;
  /// Denormalized category name kept in sync with [categoryId]. Used as a
  /// display fallback when the FK link is missing (legacy rows pre-FK).
  String category;
  /// FK to `public.inventory_categories.id`. Canonical link — UI sources
  /// the category name + icon from the [AppState] cache via this id.
  String? categoryId;
  StockUnit unit;
  /// Optional free-form symbol used for *display only* (e.g. "shot",
  /// "slice", "tray"). When set, the UI shows this instead of [unit.symbol].
  /// Recipe math always uses [unit] so g↔kg conversions still work.
  String? unitLabel;

  /// Current stock amount, in the item's [unit].
  double currentStock;

  /// Low-stock threshold (in [unit]). Items at or below this trigger alerts.
  double lowStockThreshold;

  /// Cost per single unit (e.g., ₱ per gram, per piece). Used for COGS.
  double costPerUnit;

  String supplier;
  DateTime? lastRestockedAt;

  InventoryItem({
    String? id,
    required this.name,
    this.sku = '',
    this.category = 'General',
    this.categoryId,
    required this.unit,
    this.unitLabel,
    this.currentStock = 0,
    this.lowStockThreshold = 0,
    this.costPerUnit = 0,
    this.supplier = '',
    this.lastRestockedAt,
  }) : id = id ?? _uuid.v4();

  /// The label shown in lists, badges, and recipe rows. Falls back to the
  /// preset symbol when no override is set.
  String get displayUnit {
    final override = unitLabel?.trim();
    if (override == null || override.isEmpty) return unit.symbol;
    return override;
  }

  factory InventoryItem.fromRow(Map<String, dynamic> row) => InventoryItem(
        id: row['id'] as String,
        name: row['name'] as String,
        sku: (row['sku'] as String?) ?? '',
        category: (row['category'] as String?) ?? 'General',
        categoryId: row['inventory_category_id'] as String?,
        unit: StockUnitX.fromDb(row['unit'] as String?),
        unitLabel: row['unit_label'] as String?,
        currentStock:
            (row['current_stock'] as num?)?.toDouble() ?? 0,
        lowStockThreshold:
            (row['low_stock_threshold'] as num?)?.toDouble() ?? 0,
        costPerUnit:
            ((row['cost_per_unit_cents'] as int?) ?? 0) / 100,
        supplier: (row['supplier'] as String?) ?? '',
        lastRestockedAt: (row['last_restocked_at'] as String?) != null
            ? DateTime.tryParse(row['last_restocked_at'] as String)
            : null,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'name': name.trim(),
        'sku': sku.trim(),
        'category': category,
        'inventory_category_id': categoryId,
        'unit': unit.dbValue,
        'unit_label': unitLabel?.trim().isEmpty ?? true ? null : unitLabel!.trim(),
        'current_stock': currentStock,
        'low_stock_threshold': lowStockThreshold,
        'cost_per_unit_cents': (costPerUnit * 100).round(),
        'supplier': supplier.trim(),
        'last_restocked_at': lastRestockedAt?.toIso8601String(),
      };

  bool get isLowStock =>
      lowStockThreshold > 0 && currentStock <= lowStockThreshold;

  bool get isOutOfStock => currentStock <= 0;

  /// 0..1 fill ratio relative to a sensible "full" amount (max of current
  /// and 2× threshold). Used for the visual stock bar.
  double get fillRatio {
    final cap = lowStockThreshold > 0
        ? (lowStockThreshold * 2)
        : (currentStock > 0 ? currentStock : 1);
    if (cap <= 0) return 0;
    return (currentStock / cap).clamp(0, 1);
  }
}

/// Common categories owners pick when adding inventory items.
const List<String> kInventoryCategories = [
  'Coffee & Tea',
  'Dairy',
  'Syrups & Sauces',
  'Bakery',
  'Food Ingredients',
  'Packaging',
  'Cleaning',
  'Other',
];
