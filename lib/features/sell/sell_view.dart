import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/glass.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;
import '../cafe/product_detail_sheet.dart';
import '../widgets/push_toast.dart';
import 'shift_bar.dart';

/// Unified storefront for the coffee shop. Search + category chips on top,
/// product grid below. Tapping a drink opens the modifier sheet, tapping a
/// food item adds it straight to the cart.
class SellView extends StatefulWidget {
  const SellView({super.key});

  @override
  State<SellView> createState() => _SellViewState();
}

class _SellViewState extends State<SellView> {
  /// Selected category id (the real DB FK). null = "All".
  String? _filterCategoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Show everything the owner marked Available. We no longer hide items
    // that are short on ingredient stock — instead the tile stays visible
    // with a "Not available" badge so the cashier can answer "do you have
    // Alfredo?" at a glance. (Selling is blocked on out-of-stock tiles.)
    final items = state.products.where((p) => p.available).toList();

    // Chips = tenant-owned categories from the DB, in their declared
    // sort_order. The legacy `CafeCategory` enum was only ever filled in
    // for in-memory mock data; every DB-backed product hardcodes
    // CafeCategory.food regardless of its real category, which is why
    // filtering on the enum bucketed everything under Food.
    final usedCategoryIds = items
        .map((p) => p.categoryId)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
    final usedCategories = state.categories
        .where((c) => usedCategoryIds.contains(c.id))
        .toList()
      ..sort(_categoryRank);

    // Default-select the first category once products are loaded so the
    // cashier never lands on an "all categories" view (we don't ship the
    // "All" chip anymore — owner wants Coffee → Food → rest priority).
    if (_filterCategoryId == null && usedCategories.isNotEmpty) {
      _filterCategoryId = usedCategories.first.id;
    } else if (_filterCategoryId != null &&
        !usedCategories.any((c) => c.id == _filterCategoryId)) {
      // The selected category disappeared (e.g. owner deleted it or its
      // last in-stock product). Fall back to the first available.
      _filterCategoryId =
          usedCategories.isEmpty ? null : usedCategories.first.id;
    }

    final filtered = _filterItems(items);

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          const ShiftBar(),
          Container(height: 0.5, color: YColor.hairline),
          if (!state.hasOpenShift)
            Expanded(child: _cashierClosed(context))
          else ...[
            _header(usedCategories: usedCategories),
            Expanded(
              child: filtered.isEmpty
                  ? _empty()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 140),
                      child: _grid(filtered, state),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<CafeItem> _filterItems(List<CafeItem> all) {
    var list = all;
    if (_filterCategoryId != null) {
      list = list.where((p) => p.categoryId == _filterCategoryId).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.subtitle.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Widget _header({required List<cat.Category> usedCategories}) {
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Search drinks, pastries, food…',
              hintStyle: YFont.body().copyWith(color: YColor.inkSubtle),
              filled: true,
              fillColor: YColor.surface2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // No "All" chip — cashiers always land on a real category
            // (Coffee → Food → rest). Tapping a chip swaps the grid.
            child: Row(children: [
              for (final c in usedCategories)
                _chip(
                  label: c.name,
                  icon: resolveIcon(iconName: c.iconName, name: c.name),
                  selected: _filterCategoryId == c.id,
                  onTap: () => setState(() => _filterCategoryId = c.id),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 16, color: selected ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 7),
            Text(label,
                style: YFont.bodyStrong().copyWith(
                  color: selected ? Colors.white : YColor.ink,
                )),
          ]),
        ),
      ),
    );
  }

  /// Shown instead of the catalog when no cashier shift is open — selling is
  /// blocked until the drawer is opened with a starting float.
  Widget _cashierClosed(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_clock_outlined,
                  size: 38, color: YColor.brandDeep),
            ),
            const SizedBox(height: 16),
            Text('Cashier is closed', style: YFont.titleMD()),
            const SizedBox(height: 4),
            Text('Open the cashier with your starting cash to begin selling.',
                textAlign: TextAlign.center,
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => showOpenCashier(context),
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('Open Cashier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.local_cafe_outlined,
                  size: 38, color: YColor.brandDeep),
            ),
            const SizedBox(height: 14),
            Text(
              _query.isEmpty ? 'Nothing on the menu yet' : 'No matches',
              style: YFont.titleMD().copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _query.isEmpty
                  ? 'Head to Products to add drinks and food.'
                  : 'Try a different search or clear the filter.',
              style: YFont.caption(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<CafeItem> items, AppState state) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.92,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final buildable = state.buildableCount(item);
        return _CafeCard(
          item: item,
          buildable: buildable,
          onTap: buildable <= 0
              ? () => _showOutOfStock(item)
              : () => _openSheet(item),
        );
      },
    );
  }

  void _showOutOfStock(CafeItem item) {
    PushToast.show(
      context,
      title: '${item.name} is not available',
      subtitle: 'An ingredient is out of stock. Restock it in Inventory.',
      leadingIcon: Icons.report_gmailerrorred_outlined,
    );
  }

  void _openSheet(CafeItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => ProductDetailSheet(item: item),
    );
  }

  /// Category ordering for the chip row: Coffee first, Food second, then
  /// everything else by the owner's declared sort_order (then name). Owner
  /// asked for this priority because cafe staff almost always start with
  /// a drink, then food, then misc add-ons / merch.
  int _categoryRank(cat.Category a, cat.Category b) {
    int weight(cat.Category c) {
      final n = c.name.toLowerCase();
      if (n.startsWith('coffee')) return 0;
      if (n == 'food' || n.startsWith('food')) return 1;
      return 2;
    }
    final wa = weight(a);
    final wb = weight(b);
    if (wa != wb) return wa.compareTo(wb);
    final s = a.sortOrder.compareTo(b.sortOrder);
    return s != 0 ? s : a.name.compareTo(b.name);
  }
}

class _CafeCard extends StatelessWidget {
  const _CafeCard({
    required this.item,
    required this.onTap,
    this.buildable = AppState.kUnlimitedBuild,
  });
  final CafeItem item;
  final VoidCallback onTap;

  /// How many can be made from current stock. <= 0 renders the tile as
  /// "Not available"; a small finite count shows a "N left" badge.
  final int buildable;

  @override
  Widget build(BuildContext context) {
    final out = buildable <= 0;
    final low =
        !out && buildable < AppState.kUnlimitedBuild && buildable <= 5;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: out ? 0.6 : 1,
        child: YBrightCard(
        corner: YRadius.lg,
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(YRadius.md),
                          child: Image.network(
                            item.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _sellTileFallback(item),
                          ),
                        )
                      : _sellTileFallback(item),
                ),
                if (item.tag != null)
                  Positioned(top: 8, left: 8, child: _tag(item.tag!)),
                if (out)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _stockBadge('NOT AVAILABLE', YColor.danger),
                  )
                else if (low)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _stockBadge('$buildable LEFT', YColor.brandDeep),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.basePrice.formatted, style: YFont.price()),
                  const SizedBox(height: 2),
                  Text(item.name,
                      style: YFont.body(),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: YFont.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _stockBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _sellTileFallback(CafeItem item) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: YColor.brandTint,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Center(
        child: NameIconOrEmoji(
          name: item.name,
          iconName: item.iconName,
          iconSize: 48,
        ),
      ),
    );
  }

  Widget _tag(TagKind t) {
    final (label, fg, bg) = switch (t) {
      TagKind.hit => ('HIT', YColor.danger, YColor.dangerSoft),
      TagKind.$new => ('NEW', YColor.success, YColor.successSoft),
      TagKind.sale => ('SALE', YColor.brandDeep, YColor.brandTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: fg,
        ),
      ),
    );
  }
}
