import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/stores/catalog_store.dart';
import '../../app/stores/inventory_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/glass.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;
import '../cafe/product_detail_sheet.dart';
import '../maintenance/maintenance_view.dart'
    show showProductTypeEditor, showSubTypeEditor;
import '../products/products_view.dart'
    show showProductEditor, showProductQuickEdit;
import '../widgets/push_toast.dart';
import 'reorder_grid.dart';
import 'sell_search_field.dart';
import 'shift_bar.dart';

/// Shared 0.5px hairline divider — const so it never rebuilds.
const Widget _hairline =
    SizedBox(height: 0.5, child: ColoredBox(color: YColor.hairline));

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

  /// Global search query. Empty = browsing by type/sub-type. Set when the user
  /// commits a search ("Show all" / Done) from the floating search card, which
  /// switches the grid to global results across every available product.
  String _query = '';

  /// Backing controller for the small header search pill + its accessory card.
  final TextEditingController _searchC = TextEditingController();

  /// "Arrange mode" — entered by a 3s long-press on a Type box. Shows dashed
  /// borders, drag-to-reorder, and dashed "+" add boxes across all 3 levels.
  bool _editMode = false;

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  bool get _realTypeSelected =>
      _filterTypeId != null && _filterTypeId != _kOtherType;

  @override
  Widget build(BuildContext context) {
    // Read AppState non-reactively, then subscribe ONLY to the two flags the
    // grid depends on. This stops a post-sale notifyListeners (ordersToday++,
    // refreshOrders) from rebuilding the whole product grid every time.
    final state = context.read<AppState>();
    final arrangeMode = context.select<AppState, bool>((s) => s.arrangeMode);
    final hasOpenShift = context.select<AppState, bool>((s) => s.hasOpenShift);
    // Catalog data (products / types / sub-types) lives in CatalogStore.
    final catalog = context.watch<CatalogStore>();
    // Keep tile "Not available" badges + buildable counts live when stock moves.
    context.watch<InventoryStore>();
    // Mirror arrange mode into the local flag the build + helpers read.
    _editMode = arrangeMode;
    // Show everything the owner marked Available. We no longer hide items
    // that are short on ingredient stock — instead the tile stays visible
    // with a "Not available" badge so the cashier can answer "do you have
    // Alfredo?" at a glance. (Selling is blocked on out-of-stock tiles.)
    final items = catalog.products.where((p) => p.available).toList();

    // ── Level 1: bucket products by their effective Product Type (the
    // product's own type, else its sub-type's type, else null = "Other").
    // Only types that actually have products ever render — empty ones can't
    // crash anything because they simply don't appear.
    final typeBuckets = <String?, List<CafeItem>>{};
    for (final p in items) {
      (typeBuckets[catalog.effectiveTypeId(p)] ??= <CafeItem>[]).add(p);
    }
    // Sort by sortOrder so the normal Sell view matches Customize/edit mode
    // (which sorts the same way) — otherwise the in-memory list order can drift
    // and the two views show types in a different order.
    final orderedTypes = [...catalog.productTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final typeBoxes = <_TypeEntry>[
      for (final t in orderedTypes)
        if (typeBuckets.containsKey(t.id))
          _TypeEntry(id: t.id, name: t.name, iconName: t.iconName),
    ];
    if (typeBuckets.containsKey(null)) {
      // Orphans (no resolvable type) get a catch-all box so they're never lost.
      typeBoxes.add(const _TypeEntry(
          id: _kOtherType, name: 'Other', isOther: true));
    }

    // Auto-select / validate the active type box. In edit (Customize) mode ANY
    // product type is selectable — even empty ones — so the owner can open an
    // empty type to add categories to it (without the selection bouncing back).
    final selectableTypeIds = <String>{
      ...typeBoxes.map((t) => t.id),
      if (_editMode) ...catalog.productTypes.map((t) => t.id),
    };
    if (selectableTypeIds.isEmpty) {
      _filterTypeId = null;
    } else if (_filterTypeId == null ||
        !selectableTypeIds.contains(_filterTypeId)) {
      _filterTypeId = typeBoxes.isNotEmpty
          ? typeBoxes.first.id
          : catalog.productTypes.first.id;
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
          catalog.categoriesForType(_filterTypeId).map((c) => c.id).toSet();
      final present = <String>{};
      for (final p in inType) {
        final cid = p.categoryId;
        if (cid != null && catsOfType.contains(cid)) {
          present.add(cid);
        } else {
          hasOrphanCats = true;
        }
      }
      subTypes.addAll(catalog
          .categoriesForType(_filterTypeId)
          .where((c) => present.contains(c.id)));
    }

    // Validate the selected sub-type chip against what's actually present. In
    // edit mode also allow any (even empty) category of the selected type, so
    // tapping an empty category sticks and you can add products to it.
    final validCatIds = <String>{
      ...subTypes.map((c) => c.id),
      if (hasOrphanCats) _kOtherCat,
      if (_editMode && _realTypeSelected)
        ...catalog.categoriesForType(_filterTypeId).map((c) => c.id),
    };
    if (_filterCategoryId != null && !validCatIds.contains(_filterCategoryId)) {
      _filterCategoryId = null;
    }

    final filtered = _filterItems(items, inType, catalog);

    // The sub-type rail shows when browsing a type that has sub-types — or, in
    // edit mode on a real type, always (so you can add the first sub-type).
    // During global search it's hidden so the grid uses the full width.
    final showRail = _query.isEmpty &&
        (subTypes.isNotEmpty ||
            hasOrphanCats ||
            (_editMode && _realTypeSelected));

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          // While a shift is OPEN the float/sales/orders + Close Cashier live
          // in the TopBar (see ShiftHeaderBar). Only the closed-state bar — the
          // Open Cashier entry point — stays on the page.
          if (!hasOpenShift) ...[
            const ShiftBar(),
            _hairline,
            Expanded(child: _cashierClosed(context)),
          ] else ...[
            _header(typeBoxes: typeBoxes, items: items),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sub-types live in a vertical box rail beside the grid so a
                  // long list scrolls in place instead of pushing the grid down
                  // or forcing a horizontal swipe.
                  if (showRail) _subTypeRail(subTypes, hasOrphanCats),
                  Expanded(child: _productArea(filtered, state)),
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
      List<CafeItem> all, List<CafeItem> inType, CatalogStore catalog) {
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      // Match the product NAME only — not sub-type or subtitle.
      return all.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    if (_filterCategoryId == null) return inType;
    if (_filterCategoryId == _kOtherCat) {
      // Products in this type with no sub-type, or one that belongs elsewhere.
      final catsOfType =
          catalog.categoriesForType(_filterTypeId).map((c) => c.id).toSet();
      return inType
          .where((p) =>
              p.categoryId == null || !catsOfType.contains(p.categoryId))
          .toList();
    }
    return inType.where((p) => p.categoryId == _filterCategoryId).toList();
  }

  Widget _header(
      {required List<_TypeEntry> typeBoxes, required List<CafeItem> items}) {
    // When searching, results are global — dim and disable the type picker so
    // it's clear it's not constraining the search.
    final searching = _query.isNotEmpty;
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEVEL 1 — Product Type boxes + the Search & Customize boxes at the
          // end of the row (reorderable + "+ Type" add box in arrange mode).
          _typeRow(typeBoxes, searching, items),
        ],
      ),
    );
  }

  /// The Search box that sits beside Customize — opens the floating result card.
  Widget _searchBox(List<CafeItem> items) {
    return SellSearchField(
      controller: _searchC,
      products: items,
      activeQuery: _query,
      onSelect: (item) async {
        _searchC.clear();
        if (_query.isNotEmpty) setState(() => _query = '');
        await _openSheet(item);
        // Belt-and-suspenders: never let the dismissed sheet bounce focus
        // back into search mode.
        if (mounted) FocusManager.instance.primaryFocus?.unfocus();
      },
      onShowMore: (q) => setState(() => _query = q),
      onClear: () {
        if (_query.isNotEmpty) setState(() => _query = '');
      },
    );
  }

  /// The Level-1 Product Type row. View mode: horizontal scroll; long-press a
  /// box 3s to enter arrange mode. Edit mode: reorderable row of all types +
  /// a dashed "+" to add; tap a box to edit it.
  Widget _typeRow(
      List<_TypeEntry> typeBoxes, bool searching, List<CafeItem> items) {
    const h = 84.0;
    if (_editMode) {
      final catalog = context.watch<CatalogStore>();
      // Types with products come first; empty ones (dimmed) sink to the end.
      final nonEmpty = <String>{};
      for (final p in catalog.products) {
        final id = catalog.effectiveTypeId(p);
        if (id != null) nonEmpty.add(id);
      }
      final types = [...catalog.productTypes]
        ..sort((a, b) {
          final ea = nonEmpty.contains(a.id) ? 0 : 1;
          final eb = nonEmpty.contains(b.id) ? 0 : 1;
          if (ea != eb) return ea - eb;
          return a.sortOrder.compareTo(b.sortOrder);
        });
      return SizedBox(
        height: h,
        child: Row(children: [
          Expanded(
            child: ReorderStrip(
              axis: Axis.horizontal,
              itemCount: types.length,
              mainExtent: 104,
              spacing: 10,
              onReorder: (from, to) => _onReorderTypes(types, from, to),
              // Center so the dashed border hugs the box's natural height
              // instead of stretching to the row height.
              itemBuilder: (i) => Center(
                child: Opacity(
                  opacity: nonEmpty.contains(types[i].id) ? 1 : 0.6,
                  child: _editChrome(
                    child: _TypeBox(
                      label: types[i].name,
                      icon: resolveIcon(
                          iconName: types[i].iconName, name: types[i].name),
                      selected: _filterTypeId == types[i].id,
                      onTap: () => setState(() {
                        _filterTypeId = types[i].id;
                        _filterCategoryId = null;
                      }),
                    ),
                    onEdit: () => _editType(types[i]),
                    radius: YRadius.lg,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _addBox(onTap: _addType, label: 'Type', width: 104, height: 76),
        ]),
      );
    }
    return SizedBox(
      height: h,
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: searching ? 0.4 : 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in typeBoxes)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _TypeBox(
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
                  ),
              ]),
            ),
          ),
        ),
        // Search box — always available (you can clear/refine even while a
        // search is applied). Sits just before Customize as a matched pair.
        const SizedBox(width: 10),
        _searchBox(items),
        // Tap to enter arrange mode — this same spot becomes the "+ Type" box
        // once you're editing. Hidden while searching.
        if (!searching) ...[
          const SizedBox(width: 10),
          _editPageButton(),
        ],
      ]),
    );
  }

  /// The "Edit sell page" entry button (view mode), sitting where the "+ Type"
  /// add box appears in edit mode.
  Widget _editPageButton() {
    return GestureDetector(
      onTap: _tryEnterEdit,
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: YColor.brandTint,
          borderRadius: BorderRadius.circular(YRadius.lg),
          border: Border.all(color: YColor.brand.withValues(alpha: 0.35)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.tune, size: 22, color: YColor.brandDeep),
          const SizedBox(height: 6),
          Text('Customize',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: YFont.caption().copyWith(
                  color: YColor.brandDeep,
                  fontWeight: FontWeight.w700,
                  height: 1.1)),
        ]),
      ),
    );
  }

  /// The vertical sub-type "box rail" beside the product grid. View mode: a
  /// scrolling list of selectable boxes (All · sub-types · Other). Edit mode:
  /// "All" stays on top, then ALL sub-types of the type as a reorderable list
  /// (tap = edit), then a dashed "+" to add one.
  Widget _subTypeRail(List<cat.Category> subTypes, bool hasOrphanCats) {
    if (_editMode && _realTypeSelected) {
      final catalog = context.watch<CatalogStore>();
      final nonEmpty = <String>{};
      for (final p in catalog.products
          .where((p) => catalog.effectiveTypeId(p) == _filterTypeId)) {
        if (p.categoryId != null) nonEmpty.add(p.categoryId!);
      }
      final all = [...catalog.categoriesForType(_filterTypeId)]
        ..sort((a, b) {
          final ea = nonEmpty.contains(a.id) ? 0 : 1;
          final eb = nonEmpty.contains(b.id) ? 0 : 1;
          if (ea != eb) return ea - eb;
          return a.sortOrder.compareTo(b.sortOrder);
        });
      return Container(
        width: 148,
        decoration: const BoxDecoration(
          color: YColor.surface1,
          border: Border(right: BorderSide(color: YColor.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: _railBox(
                label: 'All',
                icon: Icons.apps,
                selected: _filterCategoryId == null,
                onTap: () => setState(() => _filterCategoryId = null),
              ),
            ),
            Expanded(
              child: ReorderStrip(
                axis: Axis.vertical,
                itemCount: all.length,
                mainExtent: 50,
                // Each box hugs its text: short for 1 line ("Coffee"), taller
                // for 2 lines ("Hot Non-Coffee") — so the dashed border fits.
                extentFor: (i) => _subTypeExtent(all[i].name),
                spacing: 8,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                onReorder: (from, to) => _onReorderSubTypes(all, from, to),
                itemBuilder: (i) => Opacity(
                  opacity: nonEmpty.contains(all[i].id) ? 1 : 0.6,
                  child: _editChrome(
                    child: _railBox(
                      label: all[i].name,
                      icon: resolveIcon(
                          iconName: all[i].iconName, name: all[i].name),
                      selected: _filterCategoryId == all[i].id,
                      onTap: () =>
                          setState(() => _filterCategoryId = all[i].id),
                    ),
                    onEdit: () => _editSubType(all[i]),
                    radius: YRadius.md,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: _addBox(
                  onTap: _addSubType,
                  label: 'Category',
                  height: 44,
                  axis: Axis.horizontal),
            ),
          ],
        ),
      );
    }
    return Container(
      width: 148,
      decoration: const BoxDecoration(
        color: YColor.surface1,
        border: Border(right: BorderSide(color: YColor.hairline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _railPad(_railBox(
              label: 'All',
              icon: Icons.apps,
              selected: _filterCategoryId == null,
              onTap: () => setState(() => _filterCategoryId = null),
            )),
            for (final c in subTypes)
              _railPad(_railBox(
                label: c.name,
                icon: resolveIcon(iconName: c.iconName, name: c.name),
                selected: _filterCategoryId == c.id,
                onTap: () => setState(() => _filterCategoryId = c.id),
              )),
            if (hasOrphanCats)
              _railPad(_railBox(
                label: 'Other',
                icon: Icons.more_horiz,
                selected: _filterCategoryId == _kOtherCat,
                onTap: () => setState(() => _filterCategoryId = _kOtherCat),
              )),
          ],
        ),
      ),
    );
  }

  Widget _railPad(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: child);

  Widget _railBox({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? YColor.brand : YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: selected ? YColor.brand : YColor.hairline),
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
    );
  }

  /// Height for a sub-type box in edit mode — fits 1 line of text snugly, grows
  /// for 2 lines so the dashed border hugs the box instead of floating around a
  /// short one. Mirrors the _railBox text style + the rail's text width.
  double _subTypeExtent(String name) {
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: YFont.bodyStrong().copyWith(fontSize: 12, height: 1.15),
      ),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 82);
    return tp.computeLineMetrics().length >= 2 ? 50.0 : 40.0;
  }

  // ───── Arrange mode: handlers + shared bits ───────────────────────────

  /// Enter arrange mode — but only with an empty cart, so reordering can't
  /// disturb a sale in progress.
  void _tryEnterEdit() {
    final state = context.read<AppState>();
    if (state.cart.itemCount > 0) {
      PushToast.show(context,
          title: 'Finish the current order first',
          subtitle: 'Charge or clear the cart before arranging the menu.',
          leadingIcon: Icons.shopping_cart_checkout_outlined);
      return;
    }
    state.setArrangeMode(true);
  }

  // Reorder handlers — move item from→to (ReorderStrip/ReorderGrid semantics),
  // then persist. Surface a toast if the DB write fails (so a silent revert
  // can't go unnoticed).
  void _toastIfFailed(String? err) {
    if (err != null && mounted) {
      PushToast.show(context,
          title: "Couldn't save the new order",
          subtitle: err,
          leadingIcon: Icons.error_outline);
    }
  }

  Future<void> _onReorderTypes(
      List<ProductType> shown, int from, int to) async {
    final list = List<ProductType>.from(shown);
    list.insert(to, list.removeAt(from));
    _toastIfFailed(await context.read<CatalogStore>().reorderProductTypes(list));
  }

  Future<void> _onReorderSubTypes(
      List<cat.Category> shown, int from, int to) async {
    final list = List<cat.Category>.from(shown);
    list.insert(to, list.removeAt(from));
    _toastIfFailed(await context.read<CatalogStore>().reorderCategories(list));
  }

  Future<void> _onReorderProductsMove(
      List<CafeItem> shown, int from, int to) async {
    final list = List<CafeItem>.from(shown);
    list.insert(to, list.removeAt(from));
    _toastIfFailed(await context.read<CatalogStore>().reorderProducts(list));
  }

  // Add / edit — all reuse the real Maintenance/Products editors (DB-wired).
  void _addType() => showProductTypeEditor(context);
  void _editType(ProductType t) => showProductTypeEditor(context, initial: t);
  void _addSubType() => showSubTypeEditor(context,
      presetTypeId: _realTypeSelected ? _filterTypeId : null);
  void _editSubType(cat.Category c) => showSubTypeEditor(context, initial: c);
  void _addProductInline() => showProductEditor(context,
      presetTypeId: _realTypeSelected ? _filterTypeId : null,
      presetCategoryId: (_filterCategoryId != null &&
              _filterCategoryId != _kOtherCat)
          ? _filterCategoryId
          : null);
  void _editProduct(CafeItem p) => showProductQuickEdit(context, p);

  /// Overlays a dashed "you're editing" border on [child].
  Widget _editBorder(Widget child, double radius) => CustomPaint(
        foregroundPainter: _DashedBorderPainter(radius: radius),
        child: child,
      );

  /// Edit-mode wrapper for a Type/Sub-type box: dashed border + a small pencil
  /// badge. Tapping the box still SELECTS it (so you can navigate to arrange a
  /// different type/sub-type); tapping the pencil opens the name editor.
  Widget _editChrome({
    required Widget child,
    required VoidCallback onEdit,
    double radius = 12,
  }) {
    return _editBorder(
      Stack(children: [
        child,
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: YColor.brandDeep,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 3),
                ],
              ),
              child: const Icon(Icons.edit, size: 11, color: Colors.white),
            ),
          ),
        ),
      ]),
      radius,
    );
  }

  /// A dashed "+" add box. [axis] horizontal = icon+label in a Row (rail /
  /// product bar); vertical = stacked (type box).
  Widget _addBox({
    required VoidCallback onTap,
    required String label,
    double? width,
    double? height,
    Axis axis = Axis.vertical,
  }) {
    final children = <Widget>[
      const Icon(Icons.add, size: 20, color: YColor.brandDeep),
      SizedBox(width: axis == Axis.horizontal ? 6 : 0, height: axis == Axis.vertical ? 2 : 0),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: YFont.caption().copyWith(
                color: YColor.brandDeep, fontWeight: FontWeight.w700)),
      ),
    ];
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(radius: YRadius.md),
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: axis == Axis.horizontal
              ? Row(mainAxisSize: MainAxisSize.min, children: children)
              : Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  /// The product area. View mode: the normal scrolling grid. Edit mode: a
  /// reorderable grid (tap = quick-edit name/price, hold+drag = reorder with
  /// edge auto-scroll) + a dashed "+ Add product" bar.
  Widget _productArea(List<CafeItem> filtered, AppState state) {
    if (!_editMode) {
      if (filtered.isEmpty) return _empty();
      // Self-scrolling grid (no outer SingleChildScrollView) — same structure
      // as edit mode, so the first row sits right under the Product Type boxes.
      return _grid(filtered, state);
    }
    return Column(
      children: [
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No products here yet — tap "Add product".',
                      style:
                          YFont.caption().copyWith(color: YColor.inkMuted)))
              : ReorderGrid(
                  // Custom grid drag: the lifted tile is positioned in local
                  // coordinates, so it grows in place and stays under the
                  // finger even with the responsive scaler on. Tap = quick-edit,
                  // hold + drag = reorder (with edge auto-scroll).
                  itemCount: filtered.length,
                  maxTileExtent: 186,
                  childAspectRatio: 1.2,
                  spacing: 12,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  onTapItem: (i) => _editProduct(filtered[i]),
                  onReorder: (from, to) =>
                      _onReorderProductsMove(filtered, from, to),
                  itemBuilder: (i) => _editBorder(
                    _CafeCard(
                      item: filtered[i],
                      buildable: state.buildableCount(filtered[i]),
                      onTap: () {},
                    ),
                    YRadius.lg,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _addBox(
              onTap: _addProductInline,
              label: 'Add product',
              height: 48,
              axis: Axis.horizontal),
        ),
      ],
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
    // Pull up off true-center so it sits visually centred in the area above
    // the floating bottom nav (which covers the lower strip).
    return Align(
      alignment: const Alignment(0, -0.3),
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
      // Scrolls itself (no outer scroll view). primary:false so it doesn't
      // absorb the status-bar inset; a small top space sits it just under the
      // Product Type boxes.
      primary: false,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 140),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Slightly smaller tiles so ~3 product columns still fit beside the
        // sub-type rail; the grid flows to more columns when the rail is gone.
        maxCrossAxisExtent: 186,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Shorter, wider-feeling tiles (image ~half) so more rows fit and the
        // name reads big. Was 0.92 (tall, photo-heavy).
        childAspectRatio: 1.2,
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

  Future<void> _openSheet(CafeItem item) {
    return showModalBottomSheet<void>(
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
    // No outer padding — callers add spacing OUTSIDE any edit-mode dashed
    // border so the border hugs the box exactly.
    return GestureDetector(
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
                            // Tiles are ~186px wide; decode at ~2.7x, not full
                            // source res, so the grid scrolls smoothly.
                            cacheWidth: 512,
                            errorBuilder: (_, __, ___) =>
                                _sellTileFallback(item),
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
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name leads — bold and prominent so the cashier finds items
                  // by reading, not by photo. Price drops to a smaller accent.
                  Text(item.name,
                      style: YFont.bodyStrong()
                          .copyWith(fontSize: 14, height: 1.1),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                        item.openPrice
                            ? 'Custom price'
                            : item.basePrice.formatted,
                        style: YFont.bodyStrong().copyWith(
                            fontSize: 12.5, color: YColor.brandDeep)),
                    if (item.openPrice) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 11, color: YColor.brandDeep),
                    ],
                  ]),
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

/// Paints a dashed rounded-rect border — the "arrange mode" affordance.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({this.radius = 12});
  final double radius;
  static const Color color = YColor.brandDeep;
  static const double dash = 5;
  static const double gap = 4;
  static const double strokeWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final src = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in src.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = dist + dash;
        dashed.addPath(
          metric.extractPath(dist, next.clamp(0.0, metric.length)),
          Offset.zero,
        );
        dist = next + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}
