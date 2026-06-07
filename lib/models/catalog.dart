import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'money.dart';

const _uuid = Uuid();

enum CafeCategory {
  coffee('Coffee', Icons.coffee),
  tea('Tea', Icons.emoji_food_beverage),
  frappe('Frappé', Icons.icecream),
  pastry('Pastry', Icons.cake),
  food('Food', Icons.restaurant);

  final String title;
  final IconData icon;
  const CafeCategory(this.title, this.icon);
}

enum TagKind { hit, $new, sale }

/// Classifies how a product behaves in the cart and inventory.
/// Drinks support sizes/temperatures/strengths; food is rung up flat. Both
/// auto-deduct ingredients via their recipe.
enum ItemType { drink, food }

extension ItemTypeX on ItemType {
  String get label => switch (this) {
        ItemType.drink => 'Drink',
        ItemType.food => 'Food',
      };

  IconData get icon => switch (this) {
        ItemType.drink => Icons.local_cafe_outlined,
        ItemType.food => Icons.restaurant,
      };

  String get description => switch (this) {
        ItemType.drink =>
          'Beverages with sizes / temperatures / strengths. Recipe deducts ingredients.',
        ItemType.food =>
          'Kitchen items, pastries, meals. Recipe deducts ingredients.',
      };

  bool get consumesRecipe => true;
  bool get supportsModifiers => this == ItemType.drink;
}

class ModifierOption {
  final String id;
  final String name;
  final Money priceDelta;
  ModifierOption({String? id, required this.name, this.priceDelta = Money.zero})
      : id = id ?? _uuid.v4();
}

class ModifierGroup {
  final String id;
  final String name;
  final List<ModifierOption> options;
  final bool required;
  final int defaultIndex;
  ModifierGroup({
    String? id,
    required this.name,
    required this.options,
    this.required = false,
    this.defaultIndex = 0,
  }) : id = id ?? _uuid.v4();
}

class CafeItem {
  final String id;
  String name;
  String subtitle;
  /// Legacy hardcoded category (drink/tea/pastry/food) — kept for in-memory
  /// add-on rules and old code paths. DB-backed products also populate
  /// [categoryId] / [categoryName] which point at the tenant-owned
  /// `categories` row.
  CafeCategory category;
  /// FK to `public.categories.id`. Null on legacy in-memory products.
  String? categoryId;
  /// Denormalized category name from the joined row. Used for filters and
  /// display; the canonical reference is [categoryId].
  String categoryName;
  Money basePrice;
  String emoji;
  /// Curated Material-icon key (matches the icon picker used elsewhere).
  String? iconName;
  /// Public URL of an uploaded image in the `product-images` Supabase
  /// Storage bucket. When present, takes precedence over [iconName] / [emoji]
  /// in product tiles. Null/empty falls through to the icon → emoji ladder.
  String? imageUrl;
  TagKind? tag;
  List<ModifierGroup> modifierGroups;
  /// FK references into `public.modifier_groups` — owner-picked tenant
  /// master groups this product opts into. Preserves picker order.
  List<String> modifierGroupIds;

  /// Legacy behavior enum kept for in-memory CafeItem instances. DB-backed
  /// products instead resolve behavior flags (supportsModifiers,
  /// deductsStock) from the [ProductType] row referenced by [typeId].
  ItemType itemType;
  /// FK to `public.product_types.id`. Null on legacy in-memory products.
  String? typeId;
  /// Denormalized type name from the joined row.
  String typeName;

  /// Base recipe — what this product consumes from inventory at the
  /// default modifier selection. Each line refers to an [InventoryItem.id].
  List<RecipeLine> recipe;

  /// Per-modifier-option adjustments to the base recipe. Multipliers scale all
  /// base lines, additions append extra lines (e.g. Iced → +5pcs Ice).
  List<ModifierAdjustment> modifierAdjustments;

  bool available;
  int sortOrder;

  /// When false, this product sells freely — its recipe is NOT deducted from
  /// inventory and it never shows "out of stock". Gated further by the
  /// store-wide [AppState.inventoryTrackingEnabled] master switch.
  bool trackInventory;

  CafeItem({
    String? id,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.basePrice,
    required this.emoji,
    this.iconName,
    this.imageUrl,
    this.categoryId,
    this.categoryName = '',
    this.tag,
    this.itemType = ItemType.drink,
    this.typeId,
    this.typeName = '',
    this.modifierGroups = const [],
    List<String>? modifierGroupIds,
    List<RecipeLine>? recipe,
    List<ModifierAdjustment>? modifierAdjustments,
    this.available = true,
    this.sortOrder = 0,
    this.trackInventory = true,
  })  : id = id ?? _uuid.v4(),
        modifierGroupIds = modifierGroupIds ?? <String>[],
        recipe = recipe ?? <RecipeLine>[],
        modifierAdjustments =
            modifierAdjustments ?? <ModifierAdjustment>[];

  /// Hydrates from a `public.products` row. Pass joined `type` and
  /// `category` rows from the PostgREST nested select so denormalized name
  /// fields can be populated in one pass.
  factory CafeItem.fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? typeRow,
    Map<String, dynamic>? categoryRow,
  }) {
    final mgIds = <String>[];
    final raw = row['modifier_group_ids'];
    if (raw is List) {
      for (final v in raw) {
        mgIds.add(v.toString());
      }
    }

    final recipeRaw = row['recipe'];
    final recipeLines = <RecipeLine>[];
    if (recipeRaw is List) {
      for (final v in recipeRaw) {
        if (v is Map) {
          recipeLines.add(RecipeLine(
            id: (v['id'] as String?),
            inventoryItemId:
                (v['inventory_item_id'] ?? v['inventoryItemId'] ?? '').toString(),
            quantity: (v['quantity'] as num?)?.toDouble() ?? 0,
          ));
        }
      }
    }

    final adjRaw = row['modifier_adjustments'];
    final adjustments = <ModifierAdjustment>[];
    if (adjRaw is List) {
      for (final v in adjRaw) {
        if (v is Map) {
          final kind = (v['kind'] as String?) == 'addLines'
              ? AdjustmentKind.addLines
              : AdjustmentKind.multiplier;
          final addRaw = v['add_lines'];
          final addLines = <RecipeLine>[];
          if (addRaw is List) {
            for (final l in addRaw) {
              if (l is Map) {
                addLines.add(RecipeLine(
                  id: l['id'] as String?,
                  inventoryItemId: (l['inventory_item_id'] ??
                          l['inventoryItemId'] ??
                          '')
                      .toString(),
                  quantity: (l['quantity'] as num?)?.toDouble() ?? 0,
                ));
              }
            }
          }
          adjustments.add(ModifierAdjustment(
            id: v['id'] as String?,
            groupId: (v['group_id'] ?? v['groupId'] ?? '').toString(),
            optionId: (v['option_id'] ?? v['optionId'] ?? '').toString(),
            kind: kind,
            multiplier: (v['multiplier'] as num?)?.toDouble() ?? 1.0,
            addLines: addLines,
            priceDelta: Money((v['price_delta_cents'] as int?) ?? 0),
          ));
        }
      }
    }

    return CafeItem(
      id: row['id'] as String,
      name: row['name'] as String,
      subtitle: (row['subtitle'] as String?) ?? '',
      category: CafeCategory.food, // legacy enum, unused for DB-backed rows
      categoryId: row['category_id'] as String?,
      categoryName: categoryRow?['name'] as String? ?? '',
      basePrice: Money((row['base_price_cents'] as int?) ?? 0),
      emoji: (row['emoji'] as String?) ?? '',
      iconName: row['icon_name'] as String?,
      imageUrl: row['image_url'] as String?,
      tag: _tagFromDb(row['tag'] as String?),
      typeId: row['type_id'] as String?,
      typeName: typeRow?['name'] as String? ?? '',
      modifierGroupIds: mgIds,
      recipe: recipeLines,
      modifierAdjustments: adjustments,
      available: (row['available'] as bool?) ?? true,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      trackInventory: (row['track_inventory'] as bool?) ?? true,
    );
  }
}

TagKind? _tagFromDb(String? v) => switch (v) {
      'hit' => TagKind.hit,
      'new' => TagKind.$new,
      'sale' => TagKind.sale,
      _ => null,
    };

String? _tagToDb(TagKind? t) => switch (t) {
      TagKind.hit => 'hit',
      TagKind.$new => 'new',
      TagKind.sale => 'sale',
      null => null,
    };

/// Tenant-owned product behavior bucket. Created in Maintenance → Product
/// types. Mirrors a row in `public.product_types`.
class ProductType {
  final String id;
  String name;
  String? iconName;
  bool supportsModifiers;
  /// True if products of this type consume from inventory on sale (via
  /// their recipe). Drinks/food/pastry/book/retail: yes. Service: no.
  bool deductsStock;
  /// Seeded by the tenant bootstrap. Cannot be deleted from the UI; can
  /// still be renamed and re-iconned, and the behavior flags can flip.
  final bool isSystem;
  int sortOrder;

  ProductType({
    required this.id,
    required this.name,
    this.iconName,
    this.supportsModifiers = false,
    this.deductsStock = true,
    this.isSystem = false,
    this.sortOrder = 0,
  });

  factory ProductType.fromRow(Map<String, dynamic> row) => ProductType(
        id: row['id'] as String,
        name: row['name'] as String,
        iconName: row['icon_name'] as String?,
        supportsModifiers: (row['supports_modifiers'] as bool?) ?? false,
        deductsStock: (row['deducts_stock'] as bool?) ?? true,
        isSystem: (row['is_system'] as bool?) ?? false,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
}

/// Maps a [CafeItem] back to the JSON shape `public.products` expects.
/// Lives outside the class so callers don't have to wrap large payloads.
Map<String, dynamic> productRowPayload(CafeItem p, String tenantId) => {
      'tenant_id': tenantId,
      'type_id': p.typeId,
      'category_id': p.categoryId,
      'name': p.name.trim(),
      'subtitle': p.subtitle.trim(),
      'base_price_cents': p.basePrice.centavos,
      'emoji': p.emoji,
      'icon_name': p.iconName,
      'image_url': p.imageUrl,
      'tag': _tagToDb(p.tag),
      'available': p.available,
      'sort_order': p.sortOrder,
      'track_inventory': p.trackInventory,
      'modifier_group_ids': p.modifierGroupIds,
      'recipe': [
        for (final l in p.recipe)
          {
            'id': l.id,
            'inventory_item_id': l.inventoryItemId,
            'quantity': l.quantity,
          },
      ],
      'modifier_adjustments': [
        for (final a in p.modifierAdjustments)
          {
            'id': a.id,
            'group_id': a.groupId,
            'option_id': a.optionId,
            'kind':
                a.kind == AdjustmentKind.addLines ? 'addLines' : 'multiplier',
            'multiplier': a.multiplier,
            'price_delta_cents': a.priceDelta.centavos,
            'add_lines': [
              for (final l in a.addLines)
                {
                  'id': l.id,
                  'inventory_item_id': l.inventoryItemId,
                  'quantity': l.quantity,
                },
            ],
          },
      ],
    };

/// A reusable named option used in master lists for Sizes / Temperatures /
/// Strengths. Pricing is set per-product, not here.
class MasterOption {
  final String id;
  String name;
  Money priceDelta;
  MasterOption({String? id, required this.name, this.priceDelta = Money.zero})
      : id = id ?? _uuid.v4();

  /// Hydrates from a `public.modifier_options` row.
  factory MasterOption.fromRow(Map<String, dynamic> row) => MasterOption(
        id: row['id'] as String,
        name: row['name'] as String,
        priceDelta: Money((row['price_delta_cents'] as int?) ?? 0),
      );
}

/// A reusable modifier group managed in Maintenance. Products opt-in and set
/// their own per-option price deltas + recipe adjustments. Renaming the group
/// or its options in Maintenance flows through to every product that uses it.
class MasterModifierGroup {
  final String id;
  String name;
  String emoji;
  /// Curated Material-icon name picked at create time (see the icon picker in
  /// Maintenance). Null/empty falls back to keyword auto-mapping, then [emoji].
  String? iconName;
  bool required;
  int defaultIndex;
  int sortOrder;
  List<MasterOption> options;
  /// Seeded by the tenant bootstrap (Size, Temperature, Strength). The
  /// Maintenance UI shows a BUILT-IN badge and locks edit/remove on these.
  final bool isSystem;

  MasterModifierGroup({
    String? id,
    required this.name,
    this.emoji = '⚙',
    this.iconName,
    this.required = false,
    this.defaultIndex = 0,
    this.sortOrder = 0,
    List<MasterOption>? options,
    this.isSystem = false,
  })  : id = id ?? _uuid.v4(),
        options = options ?? <MasterOption>[];

  /// Hydrates from a `public.modifier_groups` row plus its joined option rows.
  factory MasterModifierGroup.fromRow(
    Map<String, dynamic> row, {
    required List<MasterOption> options,
  }) =>
      MasterModifierGroup(
        id: row['id'] as String,
        name: row['name'] as String,
        emoji: (row['emoji'] as String?) ?? '',
        iconName: row['icon_name'] as String?,
        required: (row['required'] as bool?) ?? false,
        defaultIndex: (row['default_index'] as int?) ?? 0,
        sortOrder: (row['sort_order'] as int?) ?? 0,
        options: options,
        isSystem: (row['is_system'] as bool?) ?? false,
      );
}

/// A custom product category added by the owner (on top of the built-in enum).
class CustomCategory {
  final String id;
  String name;
  String emoji;
  CustomCategory({String? id, required this.name, this.emoji = '🍽'})
      : id = id ?? _uuid.v4();
}

/// A stackable extra. Each unit added by the customer charges [priceDelta]
/// and consumes the listed [recipe] from inventory once.
class AddOn {
  final String id;
  String name;
  String emoji;
  /// Curated Material-icon name picked at create time. Falls back to emoji
  /// for legacy rows.
  String? iconName;
  /// Public URL of an uploaded image in the `product-images` bucket. Wins
  /// over [iconName] / [emoji] in renders when present.
  String? imageUrl;
  Money priceDelta;
  List<RecipeLine> recipe;
  /// Maximum quantity the customer can order in a single line. 0 = unlimited.
  int maxQuantity;

  /// FK references into `public.categories.id`. Empty set means "applies
  /// to every category" — the cashier sees it on every product.
  Set<String> applicableCategoryIds;

  int sortOrder;

  AddOn({
    String? id,
    required this.name,
    this.emoji = '✨',
    this.iconName,
    this.imageUrl,
    this.priceDelta = Money.zero,
    List<RecipeLine>? recipe,
    this.maxQuantity = 0,
    Set<String>? applicableCategoryIds,
    this.sortOrder = 0,
  })  : id = id ?? _uuid.v4(),
        recipe = recipe ?? <RecipeLine>[],
        applicableCategoryIds = applicableCategoryIds ?? <String>{};

  /// Whether this add-on is offered on a product in the given DB category.
  /// Null categoryId means "untyped" — only fully-open add-ons apply.
  bool appliesToCategory(String? categoryId) {
    if (applicableCategoryIds.isEmpty) return true;
    if (categoryId == null) return false;
    return applicableCategoryIds.contains(categoryId);
  }

  factory AddOn.fromRow(Map<String, dynamic> row) {
    final catRaw = row['applicable_category_ids'];
    final cats = <String>{};
    if (catRaw is List) {
      for (final v in catRaw) {
        cats.add(v.toString());
      }
    }
    final recipeRaw = row['recipe'];
    final recipeLines = <RecipeLine>[];
    if (recipeRaw is List) {
      for (final v in recipeRaw) {
        if (v is Map) {
          recipeLines.add(RecipeLine(
            id: v['id'] as String?,
            inventoryItemId:
                (v['inventory_item_id'] ?? v['inventoryItemId'] ?? '')
                    .toString(),
            quantity: (v['quantity'] as num?)?.toDouble() ?? 0,
          ));
        }
      }
    }
    return AddOn(
      id: row['id'] as String,
      name: row['name'] as String,
      emoji: (row['emoji'] as String?) ?? '✨',
      iconName: row['icon_name'] as String?,
      imageUrl: row['image_url'] as String?,
      priceDelta: Money((row['price_delta_cents'] as int?) ?? 0),
      recipe: recipeLines,
      maxQuantity: (row['max_quantity'] as int?) ?? 0,
      applicableCategoryIds: cats,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'name': name.trim(),
        'emoji': emoji,
        'icon_name': iconName,
        'image_url': imageUrl,
        'price_delta_cents': priceDelta.centavos,
        'max_quantity': maxQuantity,
        'applicable_category_ids': applicableCategoryIds.toList(),
        'recipe': [
          for (final l in recipe)
            {
              'id': l.id,
              'inventory_item_id': l.inventoryItemId,
              'quantity': l.quantity,
            },
        ],
        'sort_order': sortOrder,
      };
}

/// A line in a product's base recipe: how much of an inventory item the
/// product consumes per single sale at default modifiers.
class RecipeLine {
  final String id;
  String inventoryItemId;
  /// Amount in the inventory item's own unit.
  double quantity;

  RecipeLine({
    String? id,
    required this.inventoryItemId,
    required this.quantity,
  }) : id = id ?? _uuid.v4();
}

enum AdjustmentKind {
  /// Multiplies the base recipe quantities (e.g. Tall=1.0, Grande=1.4).
  multiplier,

  /// Adds extra recipe lines on top of the base (e.g. Iced adds Ice).
  addLines,
}

/// Adjustment applied when a particular modifier option is selected.
class ModifierAdjustment {
  final String id;
  String groupId;
  String optionId;
  AdjustmentKind kind;

  /// For [AdjustmentKind.multiplier]. e.g., 1.4 for Grande.
  double multiplier;

  /// For [AdjustmentKind.addLines].
  List<RecipeLine> addLines;

  /// Per-product, per-option price bump applied when this option is
  /// selected. Independent of [MasterOption.priceDelta] (which is global
  /// across all products using the group) — set this on the product form
  /// to override or fine-tune the cost for a specific product.
  /// `Money.zero` = no extra charge.
  Money priceDelta;

  ModifierAdjustment({
    String? id,
    required this.groupId,
    required this.optionId,
    required this.kind,
    this.multiplier = 1.0,
    List<RecipeLine>? addLines,
    this.priceDelta = Money.zero,
  })  : id = id ?? _uuid.v4(),
        addLines = addLines ?? <RecipeLine>[];
}

