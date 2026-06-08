import 'package:flutter/material.dart' show IconData, Icons;

/// Tenant-owned product category. Mirrors a row in `public.categories`.
///
/// Owners create their own categories ("Coffee", "Pastry", "Books",
/// "Soda", "Co-working") via Maintenance → Categories. Sellables (drinks,
/// food, retail items, services) reference one of these by [id].
class Category {
  final String id;
  String name;
  String emoji;
  /// Curated Material-icon name picked at create time (see the icon picker in
  /// Maintenance). Null/empty falls back to keyword auto-mapping, then [emoji].
  String? iconName;
  int sortOrder;
  /// FK to `public.product_types.id` — the parent Product Type this category
  /// (sub-type) belongs to. Null = unassigned; the Sell page surfaces such
  /// sub-types (and their products) under an "Other" bucket. Cleared to null
  /// automatically if the parent type is deleted (DB ON DELETE SET NULL).
  String? typeId;
  /// True for rows seeded by the tenant bootstrap. The Maintenance UI
  /// renders a BUILT-IN badge and blocks edit/remove for these so owners
  /// can't accidentally trash their starter catalog.
  final bool isSystem;

  /// When true this sub-type is settled as its own line in Reports → Sales
  /// (e.g. consigned "Books"), instead of merging into "General". Takes
  /// precedence over the parent type's flag.
  bool separateSales;

  Category({
    required this.id,
    required this.name,
    this.emoji = '',
    this.iconName,
    this.sortOrder = 0,
    this.typeId,
    this.isSystem = false,
    this.separateSales = false,
  });

  factory Category.fromRow(Map<String, dynamic> row) => Category(
        id: row['id'] as String,
        name: row['name'] as String,
        emoji: (row['emoji'] as String?) ?? '',
        iconName: row['icon_name'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
        typeId: row['type_id'] as String?,
        isSystem: (row['is_system'] as bool?) ?? false,
        separateSales: (row['separate_sales'] as bool?) ?? false,
      );
}

/// Per-tenant feature flags from `public.tenant_features`. Drives which nav
/// tabs (Bookings, Sessions, Members) appear in the app. The `sell` mode is
/// implicit — every tenant has it — so it isn't tracked here.
class TenantFeatures {
  bool reserveEnabled;
  bool timerEnabled;
  bool subscribeEnabled;
  bool serviceEnabled;

  TenantFeatures({
    this.reserveEnabled = false,
    this.timerEnabled = false,
    this.subscribeEnabled = false,
    this.serviceEnabled = false,
  });

  factory TenantFeatures.fromRow(Map<String, dynamic> row) => TenantFeatures(
        reserveEnabled: (row['reserve_enabled'] as bool?) ?? false,
        timerEnabled: (row['timer_enabled'] as bool?) ?? false,
        subscribeEnabled: (row['subscribe_enabled'] as bool?) ?? false,
        serviceEnabled: (row['service_enabled'] as bool?) ?? false,
      );

  TenantFeatures copy() => TenantFeatures(
        reserveEnabled: reserveEnabled,
        timerEnabled: timerEnabled,
        subscribeEnabled: subscribeEnabled,
        serviceEnabled: serviceEnabled,
      );
}

/// The 6 sellable "packs" offered at onboarding — the owner picks the ones
/// their business uses, we seed matching starter categories + flip the
/// right [TenantFeatures] flags.
enum SellPack {
  coffee,
  food,
  drinks,
  books,
  coworking,
  memberships,
}

extension SellPackX on SellPack {
  String get label => switch (this) {
        SellPack.coffee => 'Coffee',
        SellPack.food => 'Food / Pastries',
        SellPack.drinks => 'Non-coffee drinks',
        SellPack.books => 'Books / Retail',
        SellPack.coworking => 'Co-working',
        SellPack.memberships => 'Memberships',
      };

  String get emoji => switch (this) {
        SellPack.coffee => '☕',
        SellPack.food => '🥐',
        SellPack.drinks => '🥤',
        SellPack.books => '📚',
        SellPack.coworking => '🪑',
        SellPack.memberships => '🎫',
      };

  /// Themed Material icon for the chip — outlined family, matches the rest
  /// of the app's iconography. Used in onboarding + Settings.
  IconData get icon => switch (this) {
        SellPack.coffee => Icons.coffee_outlined,
        SellPack.food => Icons.bakery_dining_outlined,
        SellPack.drinks => Icons.local_drink_outlined,
        SellPack.books => Icons.menu_book_outlined,
        SellPack.coworking => Icons.chair_outlined,
        SellPack.memberships => Icons.card_membership_outlined,
      };

  String get description => switch (this) {
        SellPack.coffee => 'Espresso, drip, signature drinks',
        SellPack.food => 'Pastries, sandwiches, meals',
        SellPack.drinks => 'Soda, juice, milk tea, smoothies',
        SellPack.books => 'Books, mugs, merchandise',
        SellPack.coworking => 'Day passes, hot desks, meeting rooms',
        SellPack.memberships => 'Monthly recurring plans',
      };

  /// Starter categories seeded into `public.categories` when this pack is
  /// selected. Owners can rename, reorder, or delete them later. The
  /// [iconName] keys match entries in `kCuratedIcons` so seeded categories
  /// show themed Material icons from day one.
  List<({String name, String emoji, String iconName, int sortOrder})>
      get seedCategories => switch (this) {
            SellPack.coffee => [
                (
                  name: 'Coffee',
                  emoji: '☕',
                  iconName: 'coffee_outlined',
                  sortOrder: 10
                ),
                (
                  name: 'Tea',
                  emoji: '🍵',
                  iconName: 'emoji_food_beverage_outlined',
                  sortOrder: 20
                ),
              ],
            SellPack.food => [
                (
                  name: 'Pastry',
                  emoji: '🥐',
                  iconName: 'bakery_dining_outlined',
                  sortOrder: 30
                ),
                (
                  name: 'Food',
                  emoji: '🍽',
                  iconName: 'restaurant_outlined',
                  sortOrder: 40
                ),
              ],
            SellPack.drinks => [
                (
                  name: 'Soda',
                  emoji: '🥤',
                  iconName: 'local_drink_outlined',
                  sortOrder: 50
                ),
                (
                  name: 'Milk Tea',
                  emoji: '🧋',
                  iconName: 'local_drink_outlined',
                  sortOrder: 60
                ),
                (
                  name: 'Smoothie',
                  emoji: '🥭',
                  iconName: 'blender_outlined',
                  sortOrder: 70
                ),
              ],
            SellPack.books => [
                (
                  name: 'Books',
                  emoji: '📚',
                  iconName: 'menu_book_outlined',
                  sortOrder: 80
                ),
                (
                  name: 'Merchandise',
                  emoji: '👕',
                  iconName: 'shopping_bag_outlined',
                  sortOrder: 90
                ),
              ],
            SellPack.coworking => [
                (
                  name: 'Day Pass',
                  emoji: '🎟',
                  iconName: 'confirmation_number_outlined',
                  sortOrder: 100
                ),
                (
                  name: 'Hot Desk',
                  emoji: '🪑',
                  iconName: 'chair_outlined',
                  sortOrder: 110
                ),
                (
                  name: 'Meeting Room',
                  emoji: '📅',
                  iconName: 'meeting_room_outlined',
                  sortOrder: 120
                ),
              ],
            SellPack.memberships => [
                (
                  name: 'Memberships',
                  emoji: '🎫',
                  iconName: 'card_membership_outlined',
                  sortOrder: 130
                ),
              ],
          };
}
