import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// Shared icon system used across Maintenance, Products, Payroll, Add-ons,
/// and anywhere else that needs a themed Material-icon picker. Everything
/// is global so feature files don't re-import helpers from maintenance_view.
///
/// Precedence used by [NameIconOrEmoji]:
///   1. explicit [iconName] picked by the owner (curated key),
///   2. keyword auto-mapping from [name] (Coffee, Size, …),
///   3. [fallbackIcon] — always a Material icon so the UI stays themed.

class CuratedIcon {
  final String key;
  final IconData icon;
  final String label;
  const CuratedIcon(this.key, this.icon, this.label);
}

/// Curated outlined Material icons offered to the owner when creating or
/// editing categories, modifier groups, leave types, and add-ons. [key] is
/// the stable string stored in DB columns (`icon_name`); the order/labels
/// here can evolve without further migration.
const List<CuratedIcon> kCuratedIcons = [
  // Drinks
  CuratedIcon('coffee_outlined', Icons.coffee_outlined, 'Coffee'),
  CuratedIcon('local_cafe_outlined', Icons.local_cafe_outlined, 'Cafe'),
  CuratedIcon('emoji_food_beverage_outlined',
      Icons.emoji_food_beverage_outlined, 'Tea'),
  CuratedIcon('local_drink_outlined', Icons.local_drink_outlined, 'Drink'),
  CuratedIcon('blender_outlined', Icons.blender_outlined, 'Smoothie'),
  CuratedIcon('icecream_outlined', Icons.icecream_outlined, 'Frappé'),
  CuratedIcon('sports_bar_outlined', Icons.sports_bar_outlined, 'Beer'),
  CuratedIcon('wine_bar_outlined', Icons.wine_bar_outlined, 'Wine'),
  CuratedIcon('water_drop_outlined', Icons.water_drop_outlined, 'Milk'),
  // Food
  CuratedIcon('restaurant_outlined', Icons.restaurant_outlined, 'Food'),
  CuratedIcon('bakery_dining_outlined', Icons.bakery_dining_outlined, 'Pastry'),
  CuratedIcon('lunch_dining_outlined', Icons.lunch_dining_outlined, 'Lunch'),
  CuratedIcon('dinner_dining_outlined', Icons.dinner_dining_outlined, 'Dinner'),
  CuratedIcon('fastfood_outlined', Icons.fastfood_outlined, 'Fast food'),
  CuratedIcon('ramen_dining_outlined', Icons.ramen_dining_outlined, 'Noodles'),
  CuratedIcon('cake_outlined', Icons.cake_outlined, 'Cake'),
  CuratedIcon('cookie_outlined', Icons.cookie_outlined, 'Cookie'),
  CuratedIcon('set_meal_outlined', Icons.set_meal_outlined, 'Set meal'),
  // Retail / books / merch
  CuratedIcon('menu_book_outlined', Icons.menu_book_outlined, 'Books'),
  CuratedIcon('shopping_bag_outlined', Icons.shopping_bag_outlined, 'Retail'),
  CuratedIcon('store_outlined', Icons.store_outlined, 'Store'),
  CuratedIcon('checkroom_outlined', Icons.checkroom_outlined, 'Apparel'),
  CuratedIcon('redeem_outlined', Icons.redeem_outlined, 'Gift'),
  // Lifestyle / art / gifts
  CuratedIcon('local_florist_outlined', Icons.local_florist_outlined, 'Flowers'),
  CuratedIcon('palette_outlined', Icons.palette_outlined, 'Art'),
  CuratedIcon('brush_outlined', Icons.brush_outlined, 'Paint'),
  CuratedIcon('auto_awesome_outlined', Icons.auto_awesome_outlined, 'Stickers'),
  CuratedIcon('spa_outlined', Icons.spa_outlined, 'Spa'),
  CuratedIcon('toys_outlined', Icons.toys_outlined, 'Toys'),
  // Workspace / services / memberships
  CuratedIcon('chair_outlined', Icons.chair_outlined, 'Seat'),
  CuratedIcon('meeting_room_outlined', Icons.meeting_room_outlined, 'Room'),
  CuratedIcon(
      'card_membership_outlined', Icons.card_membership_outlined, 'Member'),
  CuratedIcon('confirmation_number_outlined',
      Icons.confirmation_number_outlined, 'Pass'),
  CuratedIcon('handshake_outlined', Icons.handshake_outlined, 'Service'),
  CuratedIcon('schedule_outlined', Icons.schedule_outlined, 'Schedule'),
  // Modifier-flavored
  CuratedIcon('straighten_outlined', Icons.straighten_outlined, 'Size'),
  CuratedIcon('thermostat_outlined', Icons.thermostat_outlined, 'Temperature'),
  CuratedIcon('bolt_outlined', Icons.bolt_outlined, 'Strength'),
  CuratedIcon('tune_outlined', Icons.tune_outlined, 'Options'),
  // General fallbacks
  CuratedIcon('label_outlined', Icons.label_outlined, 'Label'),
  CuratedIcon('local_offer_outlined', Icons.local_offer_outlined, 'Tag'),
  CuratedIcon('sell_outlined', Icons.sell_outlined, 'Sell'),
  CuratedIcon('category_outlined', Icons.category_outlined, 'Category'),
  CuratedIcon('bookmark_outline', Icons.bookmark_outline, 'Bookmark'),
  CuratedIcon('star_outline', Icons.star_outline, 'Star'),
];

/// Returns the [IconData] for a stored `icon_name` value, or null if the key
/// is unknown. Callers should fall back to keyword auto-mapping or emoji.
IconData? iconFromKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final c in kCuratedIcons) {
    if (c.key == key) return c.icon;
  }
  return null;
}

/// Maps a category / modifier-group / leave-type name to a themed outlined
/// Material icon. Returns null for unrecognised names so the caller can
/// fall back to the row's emoji field (covers custom names the owner adds).
IconData? materialIconForName(String name) {
  final n = name.toLowerCase().trim();
  // Categories
  if (n == 'coffee') return Icons.coffee_outlined;
  if (n == 'tea') return Icons.emoji_food_beverage_outlined;
  if (n == 'pastry' || n == 'pastries') return Icons.bakery_dining_outlined;
  if (n == 'food' || n == 'meals') return Icons.restaurant_outlined;
  if (n == 'soda' || n.contains('soft drink')) {
    return Icons.local_drink_outlined;
  }
  if (n == 'milk tea' || n == 'milktea') return Icons.local_drink_outlined;
  if (n == 'smoothie' || n == 'smoothies') return Icons.blender_outlined;
  if (n == 'juice' || n == 'juices') return Icons.local_drink_outlined;
  if (n == 'frappe' || n == 'frappé') return Icons.icecream_outlined;
  if (n == 'books' || n == 'book') return Icons.menu_book_outlined;
  if (n.contains('merch')) return Icons.shopping_bag_outlined;
  if (n == 'day pass') return Icons.confirmation_number_outlined;
  if (n.contains('hot desk') || n == 'desk') return Icons.chair_outlined;
  if (n.contains('meeting')) return Icons.meeting_room_outlined;
  if (n.contains('member')) return Icons.card_membership_outlined;
  if (n == 'retail') return Icons.shopping_bag_outlined;
  if (n == 'service' || n == 'services') return Icons.handshake_outlined;
  // Modifier groups
  if (n == 'size') return Icons.straighten_outlined;
  if (n == 'temperature' || n == 'temp') return Icons.thermostat_outlined;
  if (n == 'strength') return Icons.bolt_outlined;
  if (n == 'milk' || n == 'milk type') return Icons.water_drop_outlined;
  if (n == 'sweetness' || n == 'sugar') return Icons.cookie_outlined;
  return null;
}

/// Convenience resolver — returns the IconData to render given the curated
/// key, the row name, and an optional explicit fallback. Used by callers
/// that just need the IconData (e.g., to render inside a chip) without the
/// full [NameIconOrEmoji] widget wrapper.
IconData resolveIcon({
  String? iconName,
  required String name,
  IconData fallback = Icons.label_outlined,
}) {
  return iconFromKey(iconName) ?? materialIconForName(name) ?? fallback;
}

/// Renders a product / add-on visual using the precedence ladder:
///   1. uploaded image (square thumbnail, cover-fit) when [imageUrl] is set,
///   2. otherwise falls through to [NameIconOrEmoji] (icon by key,
///      keyword-mapped icon, or fallback icon).
///
/// Use this for tiles inside the Sell grid, Cart, Orders, Reports, etc. —
/// anywhere a product / add-on has an associated image. The image renders
/// at [size] × [size] with rounded corners matching the rest of the UI.
class ProductVisual extends StatelessWidget {
  const ProductVisual({
    super.key,
    required this.imageUrl,
    required this.name,
    this.iconName,
    this.size = 44,
    this.iconSize = 24,
    this.borderRadius = 10,
    this.fallbackIcon = Icons.label_outlined,
    this.iconColor,
    this.tintBackground = true,
  });

  final String? imageUrl;
  final String name;
  final String? iconName;
  final double size;
  final double iconSize;
  final double borderRadius;
  final IconData fallbackIcon;
  final Color? iconColor;
  final bool tintBackground;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconBox(),
        ),
      );
    }
    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tintBackground
            ? YColor.brandTint.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: NameIconOrEmoji(
        name: name,
        iconName: iconName,
        fallbackIcon: fallbackIcon,
        iconSize: iconSize,
        color: iconColor,
      ),
    );
  }
}

/// Renders a themed outlined Material icon for a named row (category,
/// modifier group, leave type, etc.). Always returns a Material icon — never
/// an emoji — so the UI stays consistent even for fully custom names.
class NameIconOrEmoji extends StatelessWidget {
  const NameIconOrEmoji({
    super.key,
    required this.name,
    this.iconName,
    this.fallbackIcon = Icons.label_outlined,
    this.iconSize = 18,
    this.color,
  });

  final String name;
  final String? iconName;
  final IconData fallbackIcon;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = resolveIcon(
      iconName: iconName,
      name: name,
      fallback: fallbackIcon,
    );
    return Icon(icon, size: iconSize, color: color ?? YColor.brandDeep);
  }
}

/// Inline icon picker shown inside Category / ModifierGroup / Leave / Type
/// dialogs in place of the old emoji TextField. Tapping the tile opens a
/// bottom-sheet grid of the curated icons; the picked key flows back via
/// [onChanged]. When Auto is in effect (no explicit key, no keyword match)
/// we render [fallbackIcon] so the tile is always a Material icon.
class IconPickerField extends StatelessWidget {
  const IconPickerField({
    super.key,
    required this.value,
    required this.fallbackName,
    required this.onChanged,
    this.fallbackIcon = Icons.label_outlined,
  });

  final String? value;
  final String fallbackName;
  final IconData fallbackIcon;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final picked = iconFromKey(value);
    final auto = picked == null ? materialIconForName(fallbackName) : null;
    final showing = picked ?? auto ?? fallbackIcon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final result = await showModalBottomSheet<_IconPickResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: YColor.surface1,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => FractionallySizedBox(
            heightFactor: 0.75,
            child: _IconPickerSheet(selected: value),
          ),
        );
        if (result != null) onChanged(result.cleared ? null : result.key);
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
        ),
        alignment: Alignment.center,
        child: Icon(showing, size: 24, color: YColor.brandDeep),
      ),
    );
  }
}

class _IconPickResult {
  const _IconPickResult({this.key, this.cleared = false});
  final String? key;
  final bool cleared;
}

class _IconPickerSheet extends StatelessWidget {
  const _IconPickerSheet({this.selected});
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text('Pick an icon',
                  style: YFont.titleLG().copyWith(fontSize: 18)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop(const _IconPickResult(cleared: true)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Auto'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Auto uses the name to choose an icon (e.g. "Coffee" → ☕). '
              'Pick one below to override.',
              style: YFont.caption(),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                itemCount: kCuratedIcons.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 84,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.0,
                ),
                itemBuilder: (_, i) {
                  final c = kCuratedIcons[i];
                  final isSelected = c.key == selected;
                  return InkWell(
                    borderRadius: BorderRadius.circular(YRadius.md),
                    onTap: () => Navigator.of(context)
                        .pop(_IconPickResult(key: c.key)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? YColor.brand.withValues(alpha: 0.1)
                            : YColor.surface2,
                        borderRadius: BorderRadius.circular(YRadius.md),
                        border: Border.all(
                          color: isSelected ? YColor.brand : YColor.hairline,
                          width: isSelected ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(c.icon,
                              size: 24,
                              color: isSelected
                                  ? YColor.brand
                                  : YColor.brandDeep),
                          const SizedBox(height: 4),
                          Text(
                            c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.caption().copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
