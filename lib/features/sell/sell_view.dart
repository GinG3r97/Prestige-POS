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
  // Two-level browse: pick a Product Type box, then a Sub-type chip within it.
  // Sentinels let `null` keep meaning "All in this type".
  static const _kOtherType = '__other_type__';
  static const _kOtherCat = '__other_cat__';

  /// Selected Product Type box id; `_kOtherType` = the "Other" (untyped) box.
  String? _filterTypeId;

  /// Selected Sub-type chip within the type; null = "All", `_kOtherCat` =
  /// products here with no sub-type (or one that belongs to another type).
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

    // ── Level 1: bucket products by their effective Product Type (the
    // product's own type, else its sub-type's type, else null = "Other").
    // Only types that actually have products ever render — empty ones can't
    // crash anything because they simply don't appear.
    final typeBuckets = <String?, List<CafeItem>>{};
    for (final p in items) {
      (typeBuckets[state.effectiveTypeId(p)] ??= <CafeItem>[]).add(p);
    }
    final typeBoxes = <_TypeEntry>[
      for (final t in state.productTypes)
        if (typeBuckets.containsKey(t.id))
          _TypeEntry(id: t.id, name: t.name, iconName: t.iconName),
    ];
    if (typeBuckets.containsKey(null)) {
      // Orphans (no resolvable type) get a catch-all box so they're never lost.
      typeBoxes.add(const _TypeEntry(
          id: _kOtherType, name: 'Other', isOther: true));
    }

    // Auto-select / validate the active type box.
    if (typeBoxes.isEmpty) {
      _filterTypeId = null;
    } else if (_filterTypeId == null ||
        !typeBoxes.any((t) => t.id == _filterTypeId)) {
      _filterTypeId = typeBoxes.first.id;
      _filterCategoryId = null;
    }

    // Products inside the selected type box.
    final inType = _filterTypeId == _kOtherType
        ? (typeBuckets[null] ?? const <CafeItem>[])
        : (typeBuckets[_filterTypeId] ?? const <CafeItem>[]);

    // ── Level 2: sub-type chips for the selected (real) type — only those
    // with products here. `hasOrphanCats` = some products in this type have no
    // sub-type (or one belonging to a different type) → an "Other" chip. The
    // Other type box has no sub-type row (its items are un-bucketable).
    final subTypes = <cat.Category>[];
    var hasOrphanCats = false;
    if (_filterTypeId != null && _filterTypeId != _kOtherType) {
      final catsOfType =
          state.categoriesForType(_filterTypeId).map((c) => c.id).toSet();
      final present = <String>{};
      for (final p in inType) {
        final cid = p.categoryId;
        if (cid != null && catsOfType.contains(cid)) {
          present.add(cid);
        } else {
          hasOrphanCats = true;
        }
      }
      subTypes.addAll(state
          .categoriesForType(_filterTypeId)
          .where((c) => present.contains(c.id)));
    }

    // Validate the selected sub-type chip against what's actually present.
    final validCatIds = <String>{
      ...subTypes.map((c) => c.id),
      if (hasOrphanCats) _kOtherCat,
    };
    if (_filterCategoryId != null && !validCatIds.contains(_filterCategoryId)) {
      _filterCategoryId = null;
    }

    final filtered = _filterItems(items, inType, state);

    // The sub-type rail shows only when browsing a type that has sub-types.
    // During global search it's hidden so the grid uses the full width.
    final showRail = _query.isEmpty && (subTypes.isNotEmpty || hasOrphanCats);

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          // While a shift is OPEN the float/sales/orders + Close Cashier live
          // in the TopBar (see ShiftHeaderBar). Only the closed-state bar — the
          // Open Cashier entry point — stays on the page.
          if (!state.hasOpenShift) ...[
            const ShiftBar(),
            Container(height: 0.5, color: YColor.hairline),
            Expanded(child: _cashierClosed(context)),
          ] else ...[
            _header(typeBoxes: typeBoxes),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sub-types live in a vertical box rail beside the grid so
                  // a long list scrolls in place instead of pushing the grid
                  // down or forcing a horizontal swipe.
                  if (showRail) _subTypeRail(subTypes, hasOrphanCats),
                  Expanded(
                    child: filtered.isEmpty
                        ? _empty()
                        : SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 140),
                            child: _grid(filtered, state),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// While searching, search ALL available products (global) so the cashier
  /// can find anything regardless of the selected type/sub-type. Otherwise
  /// filter the already-type-scoped [inType] by the selected sub-type chip.
  List<CafeItem> _filterItems(
      List<CafeItem> all, List<CafeItem> inType, AppState state) {
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      return all
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.subtitle.toLowerCase().contains(q))
          .toList();
    }
    if (_filterCategoryId == null) return inType;
    if (_filterCategoryId == _kOtherCat) {
      // Products in this type with no sub-type, or one that belongs elsewhere.
      final catsOfType =
          state.categoriesForType(_filterTypeId).map((c) => c.id).toSet();
      return inType
          .where((p) =>
              p.categoryId == null || !catsOfType.contains(p.categoryId))
          .toList();
    }
    return inType.where((p) => p.categoryId == _filterCategoryId).toList();
  }

  Widget _header({required List<_TypeEntry> typeBoxes}) {
    // When searching, results are global — dim and disable the type picker so
    // it's clear it's not constraining the search.
    final searching = _query.isNotEmpty;
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
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
              ),
              const SizedBox(width: 12),
              _closeCashierButton(),
            ],
          ),
          // LEVEL 1 — Product Type boxes (Drinks, Foods, …, Other).
          if (typeBoxes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Opacity(
              opacity: searching ? 0.4 : 1,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final t in typeBoxes)
                    _TypeBox(
                      label: t.name,
                      icon: t.isOther
                          ? Icons.more_horiz
                          : resolveIcon(iconName: t.iconName, name: t.name),
                      selected: _filterTypeId == t.id,
                      onTap: searching
                          ? null
                          : () => setState(() {
                                _filterTypeId = t.id;
                                _filterCategoryId = null;
                              }),
                    ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The vertical sub-type "box rail" beside the product grid. Each sub-type is
  /// a small icon+label box; the list scrolls in place so 10+ sub-types stay
  /// findable without pushing the grid down. Always leads with "All" and ends
  /// with "Other" when the type has un-bucketed products.
  Widget _subTypeRail(List<cat.Category> subTypes, bool hasOrphanCats) {
    return Container(
      width: 148,
      decoration: const BoxDecoration(
        color: YColor.surface1,
        border: Border(right: BorderSide(color: YColor.hairline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _railBox(
              label: 'All',
              icon: Icons.apps,
              selected: _filterCategoryId == null,
              onTap: () => setState(() => _filterCategoryId = null),
            ),
            for (final c in subTypes)
              _railBox(
                label: c.name,
                icon: resolveIcon(iconName: c.iconName, name: c.name),
                selected: _filterCategoryId == c.id,
                onTap: () => setState(() => _filterCategoryId = c.id),
              ),
            if (hasOrphanCats)
              _railBox(
                label: 'Other',
                icon: Icons.more_horiz,
                selected: _filterCategoryId == _kOtherCat,
                onTap: () => setState(() => _filterCategoryId = _kOtherCat),
              ),
          ],
        ),
      ),
    );
  }

  Widget _railBox({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.md),
            border:
                Border.all(color: selected ? YColor.brand : YColor.hairline),
          ),
          child: Row(children: [
            Icon(icon,
                size: 18, color: selected ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 12,
                      height: 1.15,
                      color: selected ? Colors.white : YColor.ink)),
            ),
          ]),
        ),
      ),
    );
  }

  /// Close Cashier action sitting flush beside the search box. Mirrors the
  /// search field's fill, pill shape and vertical padding so the two read as a
  /// matched pair (same height).
  Widget _closeCashierButton() {
    return GestureDetector(
      onTap: () => showCloseCashier(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 16, color: YColor.danger),
          const SizedBox(width: 8),
          Text('Close Cashier',
              style: YFont.bodyStrong()
                  .copyWith(color: YColor.danger, fontSize: 13)),
        ]),
      ),
    );
  }

  /// Shown instead of the catalog when no cashier shift is open — selling is
  /// blocked until the drawer is opened with a starting float.
  Widget _cashierClosed(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.35),
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
            Text('Tap "Open Cashier" at the top to enter your starting cash '
                'and begin selling.',
                textAlign: TextAlign.center,
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
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
        // Slightly smaller tiles so ~3 product columns still fit beside the
        // sub-type rail; the grid flows to more columns when the rail is gone.
        maxCrossAxisExtent: 186,
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

}

/// A Level-1 Product Type entry for the Sell header (real type or the
/// synthetic "Other" catch-all).
class _TypeEntry {
  const _TypeEntry({
    required this.id,
    required this.name,
    this.iconName,
    this.isOther = false,
  });
  final String id;
  final String name;
  final String? iconName;
  final bool isOther;
}

/// The Level-1 "box" — bigger than a sub-type chip. Icon over label, brand
/// fill when selected. `onTap` null disables it (e.g. while searching).
class _TypeBox extends StatelessWidget {
  const _TypeBox({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.lg),
            border: Border.all(
                color: selected ? YColor.brand : YColor.hairline),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 26, color: selected ? Colors.white : YColor.brandDeep),
            const SizedBox(height: 8),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YFont.bodyStrong().copyWith(
                    fontSize: 13,
                    color: selected ? Colors.white : YColor.ink)),
          ]),
        ),
      ),
    );
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
