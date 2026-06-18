import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/stores/catalog_store.dart';
import '../../app/stores/inventory_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/responsive.dart';
import '../../design_system/icons.dart'
    show
        iconFromKey,
        materialIconForName,
        NameIconOrEmoji,
        ProductVisual;
import '../../design_system/spacing.dart';
import '../../design_system/themed_dropdown.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;
import '../../models/inventory.dart';
import '../../models/money.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import 'ingredient_search_field.dart';

/// Shared 0.5px hairline divider — const so it never rebuilds.
const Widget _hairline =
    SizedBox(height: 0.5, child: ColoredBox(color: YColor.hairline));

class ProductsView extends StatefulWidget {
  const ProductsView({super.key});

  @override
  State<ProductsView> createState() => _ProductsViewState();
}

enum _ProdStatus { all, active, inactive, custom }

extension _ProdStatusX on _ProdStatus {
  String get label => switch (this) {
        _ProdStatus.all => 'All status',
        _ProdStatus.active => 'Active',
        _ProdStatus.inactive => 'Inactive',
        _ProdStatus.custom => 'Custom price',
      };
}

class _ProductsViewState extends State<ProductsView> {
  String? _selectedId;
  String _query = '';
  /// Selected category id (real DB FK). null = "All".
  String? _categoryId;
  _ProdStatus _status = _ProdStatus.all;
  final TextEditingController _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Catalog data (products/categories/types/modifier groups) lives in
    // CatalogStore; inventory (the recipe ingredient picker) lives in
    // InventoryStore; cross-domain reads stay on AppState.
    final catalog = context.watch<CatalogStore>();
    final invStore = context.watch<InventoryStore>();
    final products = catalog.products;
    final filtered = _filtered(products);
    final selected = _selectedId == null
        ? null
        : products.where((p) => p.id == _selectedId).firstOrNull;

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
          // List pane
          SizedBox(
            width: panelWidth(context, fraction: 0.30, min: 300, max: 360),
            child: Container(
              color: YColor.surface1,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                      controller: _searchC,
                      accessoryLabel: 'SEARCH',
                      hint: 'Search by name…',
                      fillColor: YColor.surface2,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      onChanged: (v) => setState(() => _query = v),
                      suffix: _query.isEmpty
                          ? null
                          : GestureDetector(
                              onTap: () => setState(() {
                                _searchC.clear();
                                _query = '';
                              }),
                              child: const Icon(Icons.close_rounded,
                                  size: 17, color: YColor.inkMuted),
                            ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () => _openForm(context, state, null),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: YColor.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(YRadius.md)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  // Category + Status filters — boxes matching the search.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                    child: Row(children: [
                      Expanded(child: _categoryFilterDropdown(catalog)),
                      const SizedBox(width: 8),
                      Expanded(child: _statusFilterDropdown()),
                    ]),
                  ),
                  _hairline,
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                products.isEmpty
                                    ? 'No products yet.\nTap Add to create your first menu item.'
                                    : 'No matches.',
                                textAlign: TextAlign.center,
                                style: YFont.caption(),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => _hairline,
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              final selected = p.id == _selectedId;
                              return Material(
                                color: selected
                                    ? YColor.brandTint
                                        .withValues(alpha: 0.4)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _selectedId = p.id),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: selected
                                              ? YColor.brand
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                        13, 12, 12, 12),
                                    child: Row(children: [
                                      ProductVisual(
                                        imageUrl: p.imageUrl,
                                        name: p.name,
                                        iconName: p.iconName,
                                        size: 40,
                                        iconSize: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Expanded(
                                                child: Text(p.name,
                                                    style:
                                                        YFont.bodyStrong(),
                                                    overflow: TextOverflow
                                                        .ellipsis),
                                              ),
                                              if (!p.available)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: YColor.surface3,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(4),
                                                  ),
                                                  child: const Text(
                                                    'OFF',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.6,
                                                      color:
                                                          YColor.inkMuted,
                                                    ),
                                                  ),
                                                ),
                                            ]),
                                            const SizedBox(height: 2),
                                            Text(
                                              p.categoryName.isNotEmpty
                                                  ? p.categoryName
                                                  : p.category.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: YFont.caption(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Price as a trailing accent — scannable.
                                      Text(
                                        p.openPrice
                                            ? 'Custom'
                                            : p.basePrice.formatted,
                                        style: YFont.bodyStrong().copyWith(
                                            fontSize: 13,
                                            color: YColor.brandDeep),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(Icons.chevron_right,
                                          size: 18,
                                          color: selected
                                              ? YColor.brandDeep
                                              : YColor.inkSubtle),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 0.5, color: YColor.hairline),
          // Detail pane
          Expanded(
            child: selected == null
                ? _empty()
                // Inline, tabbed, editable details — saves in place via Update.
                : ProductFormDialog(
                    key: ValueKey(selected.id),
                    initial: selected,
                    inventory: invStore.inventory,
                    embedded: true,
                    onRemove: () => _confirmRemove(context, state, selected),
                  ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<CafeItem> _filtered(List<CafeItem> all) {
    var result = all;
    if (_categoryId != null) {
      result = result.where((p) => p.categoryId == _categoryId).toList();
    }
    result = switch (_status) {
      _ProdStatus.all => result,
      _ProdStatus.active => result.where((p) => p.available).toList(),
      _ProdStatus.inactive => result.where((p) => !p.available).toList(),
      _ProdStatus.custom => result.where((p) => p.openPrice).toList(),
    };
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.subtitle.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  Widget _categoryFilterDropdown(CatalogStore catalog) {
    final usedIds = catalog.products
        .map((p) => p.categoryId)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
    final cats = catalog.categories
        .where((c) => usedIds.contains(c.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    const allKey = '__all__';
    return ThemedDropdown<String>(
      label: 'Category',
      value: _categoryId ?? allKey,
      items: [allKey, ...cats.map((c) => c.id)],
      labelOf: (id) => id == allKey
          ? 'All'
          : (cats.where((c) => c.id == id).firstOrNull?.name ?? 'Unknown'),
      iconOf: (id) {
        if (id == allKey) return Icons.apps;
        final c = cats.where((x) => x.id == id).firstOrNull;
        return iconFromKey(c?.iconName) ??
            materialIconForName(c?.name ?? '') ??
            Icons.label_outline;
      },
      onChanged: (id) => setState(
          () => _categoryId = (id == null || id == allKey) ? null : id),
    );
  }

  Widget _statusFilterDropdown() {
    return ThemedDropdown<_ProdStatus>(
      label: 'Status',
      value: _status,
      items: _ProdStatus.values.toList(),
      labelOf: (s) => s.label,
      iconOf: (s) => switch (s) {
        _ProdStatus.all => Icons.tune,
        _ProdStatus.active => Icons.check_circle_outline,
        _ProdStatus.inactive => Icons.visibility_off_outlined,
        _ProdStatus.custom => Icons.edit_outlined,
      },
      onChanged: (s) => setState(() => _status = s ?? _ProdStatus.all),
    );
  }

  Widget _empty() {
    return Align(
      alignment: const Alignment(-0.12, -0.3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: YColor.surface3,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.local_cafe_outlined,
                size: 38, color: YColor.inkMuted),
          ),
          const SizedBox(height: 14),
          Text('Select a product',
              textAlign: TextAlign.center,
              style: YFont.titleMD().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 4),
          Text('Choose one on the left to view its recipe and details',
              textAlign: TextAlign.center,
              style: YFont.caption()),
        ],
      ),
    );
  }

  Future<void> _openForm(
      BuildContext context, AppState state, CafeItem? existing) async {
    if (existing == null) {
      final capMsg = state.planCapMessage('products');
      if (capMsg != null) {
        PushToast.show(context,
            title: 'Upgrade needed',
            subtitle: capMsg,
            leadingIcon: Icons.workspace_premium_outlined);
        return;
      }
    }
    final catalog = context.read<CatalogStore>();
    final inventory = context.read<InventoryStore>().inventory;
    final saved = await showDialog<CafeItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(
        initial: existing,
        inventory: inventory,
      ),
    );
    if (saved == null || !mounted) return;
    final err = existing == null
        ? await catalog.addProduct(saved)
        : await catalog.updateProduct(saved);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    if (existing == null) {
      final fresh = catalog.products.lastOrNull;
      setState(() => _selectedId = fresh?.id ?? saved.id);
    }
    // Pick the freshest record so toast image reflects what was saved
    // (uploaded photo URLs only exist after the server roundtrip).
    final fresh = catalog.products
            .where((p) => p.id == saved.id)
            .firstOrNull ??
        saved;
    PushToast.show(
      context,
      title: existing == null ? 'Product added' : 'Product updated',
      subtitle: saved.name,
      leadingImageUrl: fresh.imageUrl,
      leadingIconName: fresh.iconName,
      leadingEmoji: saved.emoji.isEmpty ? '☕' : saved.emoji,
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState state, CafeItem product) async {
    final ok = await showConfirm(
      context,
      title: 'Remove ${product.name}?',
      message:
          'The product will be removed from the menu. Existing orders are unaffected.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final err = await context.read<CatalogStore>().removeProduct(product.id);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    setState(() => _selectedId = null);
    PushToast.show(
      context,
      title: 'Product removed',
      subtitle: product.name,
      leadingImageUrl: product.imageUrl,
      leadingIconName: product.iconName,
      leadingIcon: Icons.delete_outline,
    );
  }
}

// ───── Form dialog ─────

/// Opens the full Product editor to ADD a product, pre-selecting
/// [presetTypeId] / [presetCategoryId]. Persists via addProduct. Reusable from
/// the Sell "arrange mode" + box.
Future<void> showProductEditor(BuildContext context,
    {String? presetTypeId, String? presetCategoryId}) async {
  final capMsg = context.read<AppState>().planCapMessage('products');
  if (capMsg != null) {
    PushToast.show(context,
        title: 'Upgrade needed',
        subtitle: capMsg,
        leadingIcon: Icons.workspace_premium_outlined);
    return;
  }
  final catalog = context.read<CatalogStore>();
  final inventory = context.read<InventoryStore>().inventory;
  final saved = await showDialog<CafeItem>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProductFormDialog(
      inventory: inventory,
      presetTypeId: presetTypeId,
      presetCategoryId: presetCategoryId,
    ),
  );
  if (saved == null || !context.mounted) return;
  final err = await catalog.addProduct(saved);
  if (!context.mounted) return;
  PushToast.show(context,
      title: err == null ? 'Product added' : 'Could not save',
      subtitle: err ?? saved.name,
      leadingIcon:
          err == null ? Icons.check_circle_outline : Icons.error_outline);
}

/// Quick-edit a product's NAME and PRICE only (image locked) — for Sell's
/// "arrange mode". Mutates just those two fields and saves via updateProduct,
/// preserving recipe/modifiers/type/category, so the full Products editor and
/// the DB stay perfectly consistent.
Future<void> showProductQuickEdit(BuildContext context, CafeItem item) async {
  final result = await showDialog<
      ({
        String name,
        int priceCents,
        bool openPrice,
        String? typeId,
        String? categoryId,
      })>(
    context: context,
    builder: (_) => _ProductQuickEditDialog(item: item),
  );
  if (result == null || !context.mounted) return;
  item.name = result.name;
  item.basePrice = Money(result.priceCents);
  item.openPrice = result.openPrice;
  item.typeId = result.typeId;
  item.categoryId = result.categoryId;
  final err = await context.read<CatalogStore>().updateProduct(item);
  if (!context.mounted) return;
  PushToast.show(context,
      title: err == null ? 'Product updated' : 'Could not save',
      subtitle: err ?? item.name,
      leadingIcon:
          err == null ? Icons.check_circle_outline : Icons.error_outline);
}

class _ProductQuickEditDialog extends StatefulWidget {
  const _ProductQuickEditDialog({required this.item});
  final CafeItem item;
  @override
  State<_ProductQuickEditDialog> createState() =>
      _ProductQuickEditDialogState();
}

class _ProductQuickEditDialogState extends State<_ProductQuickEditDialog> {
  late final TextEditingController _name;
  late String _priceStr; // numpad-driven, in pesos
  late bool _openPrice;
  String? _typeId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    final cents = widget.item.basePrice.centavos;
    _priceStr = cents % 100 == 0
        ? (cents ~/ 100).toString()
        : (cents / 100).toStringAsFixed(2);
    _openPrice = widget.item.openPrice;
    _typeId = widget.item.typeId;
    _categoryId = widget.item.categoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // ── numpad → _priceStr (ignored while custom price is on) ──
  void _press(String k) {
    if (_openPrice) return;
    setState(() {
      if (k == '⌫') {
        if (_priceStr.isNotEmpty) {
          _priceStr = _priceStr.substring(0, _priceStr.length - 1);
        }
      } else if (k == '.') {
        if (!_priceStr.contains('.')) {
          _priceStr = _priceStr.isEmpty ? '0.' : '$_priceStr.';
        }
      } else {
        final dot = _priceStr.indexOf('.');
        if (dot >= 0 && _priceStr.length - dot > 2) return; // max 2 decimals
        if (_priceStr == '0') {
          _priceStr = k; // no leading zero
        } else {
          if (_priceStr.replaceAll('.', '').length >= 7) return; // sane cap
          _priceStr += k;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final types = app.productTypes;
    final allCats = app.categories;
    // Categories scoped to the chosen type (fall back to all if none match).
    final scopedCats = _typeId == null
        ? allCats
        : (allCats.where((c) => c.typeId == _typeId).toList().isEmpty
            ? allCats
            : allCats.where((c) => c.typeId == _typeId).toList());

    final priceText = _openPrice
        ? 'Custom price'
        : (_priceStr.isEmpty ? '0' : _priceStr);

    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Quick edit', style: YFont.titleMD()),
      content: SizedBox(
        width: 640,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LEFT: name, price, type, category ──
            SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyboardAccessoryField(
                    controller: _name,
                    label: 'Name',
                    accessoryLabel: 'PRODUCT NAME',
                    hint: 'Product name',
                    fillColor: YColor.surface2,
                    borderColor: YColor.hairline,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // Price — display only; driven by the numpad on the right.
                  Text('PRICE (₱)',
                      style: YFont.caption().copyWith(
                          color: YColor.inkMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: _openPrice ? YColor.surface3 : YColor.surface2,
                      borderRadius: BorderRadius.circular(YRadius.md),
                      border: Border.all(color: YColor.hairline),
                    ),
                    child: Text(
                      _openPrice ? priceText : '₱$priceText',
                      style: YFont.titleMD().copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _openPrice ? YColor.inkMuted : YColor.ink,
                        fontStyle:
                            _openPrice ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ThemedDropdown<String>(
                    label: 'Product type',
                    value: _typeId,
                    hint: 'Choose type',
                    items: types.map((t) => t.id).toList(),
                    labelOf: (id) =>
                        types.where((t) => t.id == id).firstOrNull?.name ??
                        'Unknown',
                    onChanged: (id) => setState(() {
                      _typeId = id;
                      // Drop a category that no longer belongs to the new type.
                      final stillValid = allCats
                          .where((c) => c.id == _categoryId)
                          .firstOrNull
                          ?.typeId;
                      if (id != null && stillValid != null && stillValid != id) {
                        _categoryId = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  ThemedDropdown<String>(
                    label: 'Category',
                    value: _categoryId,
                    hint: 'Choose category',
                    items: scopedCats.map((c) => c.id).toList(),
                    labelOf: (id) =>
                        allCats.where((c) => c.id == id).firstOrNull?.name ??
                        'Unknown',
                    onChanged: (id) => setState(() => _categoryId = id),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // ── RIGHT: custom-price toggle + numpad ──
            SizedBox(
              width: 272,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: _openPrice ? YColor.brandTint : YColor.surface2,
                      borderRadius: BorderRadius.circular(YRadius.md),
                      border: Border.all(
                          color: _openPrice ? YColor.brandSoft : YColor.hairline),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          'Custom price — cashier types the price at checkout',
                          style: YFont.caption(),
                        ),
                      ),
                      Switch(
                        value: _openPrice,
                        onChanged: (v) => setState(() => _openPrice = v),
                        activeThumbColor: YColor.brand,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _Numpad(enabled: !_openPrice, onKey: _press),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () {
                  final pesos = double.tryParse(_priceStr) ?? 0;
                  Navigator.of(context).pop((
                    name: _name.text.trim(),
                    priceCents: Money.pesos(pesos).centavos,
                    openPrice: _openPrice,
                    typeId: _typeId,
                    categoryId: _categoryId,
                  ));
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Compact in-app numpad (1–9, ., 0, ⌫). Greys out and ignores taps when
/// [enabled] is false (e.g. while Custom price is on).
class _Numpad extends StatelessWidget {
  const _Numpad({required this.enabled, required this.onKey});
  final bool enabled;
  final void Function(String) onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        children: [
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final k in row)
                    GestureDetector(
                      onTap: enabled ? () => onKey(k) : null,
                      child: Container(
                        width: 80,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: YColor.surface1,
                          borderRadius: BorderRadius.circular(YRadius.md),
                          border: Border.all(color: YColor.hairline),
                        ),
                        child: Text(k,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({
    super.key,
    this.initial,
    required this.inventory,
    this.presetTypeId,
    this.presetCategoryId,
    this.embedded = false,
    this.onRemove,
  });
  final CafeItem? initial;
  final List<InventoryItem> inventory;
  /// For a NEW product, pre-select these (used by Sell "arrange mode" + box).
  final String? presetTypeId;
  final String? presetCategoryId;

  /// When true, renders inline (no Dialog chrome) as a tabbed, editable details
  /// pane that saves in place with an Update button — used on the Products page.
  final bool embedded;

  /// Embedded mode only — invoked by the Remove button in the pane header.
  final VoidCallback? onRemove;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _subtitle;
  late final TextEditingController _price;
  late CafeCategory _category;
  late ItemType _itemType;
  // DB-backed pickers — the legacy enums above stay around for now so
  // existing in-memory code paths (AddOn rules etc.) keep compiling.
  String? _typeId;
  String? _categoryId;
  late bool _available;
  late bool _openPrice;
  late bool _trackInventory;

  /// Wizard step (0=Basics, 1=Modifiers, 2=Recipe, 3=Options).
  int _step = 0;
  static const _stepTitles = ['Basics', 'Modifiers', 'Recipe', 'Options'];
  final ScrollController _scrollC = ScrollController();

  /// Change step and snap the content back to the top.
  void _setStep(int i) {
    setState(() => _step = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) _scrollC.jumpTo(0);
    });
  }

  /// Modifiers step — which group is shown in the right pane.
  String? _modGroupSel;
  // Image upload state. _imageUrl is the public URL already saved on the
  // product row (when editing). _pendingImageBytes is set when the user
  // picks a fresh photo — on Save we upload it, swap the URL, and clear.
  // _emojiFallback is preserved across saves so legacy products keep their
  // emoji glyph when no image is uploaded.
  String? _imageUrl;
  Uint8List? _pendingImageBytes;
  late String _emojiFallback;
  bool _saving = false;
  late List<RecipeLine> _recipe;
  late List<ModifierAdjustment> _adjustments;

  /// Recipe lines that actually have an ingredient picked.
  List<RecipeLine> get _cleanRecipe =>
      _recipe.where((l) => l.inventoryItemId.isNotEmpty).toList();

  /// Recipe top tab: 'base' or a modifier group id.
  String _recipeTab = 'base';

  /// Selected option id within the current group's rail.
  String _recipeSel = '';
  late List<ModifierGroup> _modifierGroups;
  /// FK ids of master modifier groups this product opts into. Source of
  /// truth on save; [_modifierGroups] is derived from these for the
  /// recipe editor's per-option adjustment tabs.
  late Set<String> _modifierGroupIds;
  // Lazy controllers for recipe quantity fields keyed by line.id
  final Map<String, TextEditingController> _qtyCtrls = {};
  // Lazy controllers for multiplier number fields, keyed by "${groupId}_${optionId}"
  final Map<String, TextEditingController> _mulCtrls = {};
  // Lazy controllers for per-option price-delta fields, same keying.
  final Map<String, TextEditingController> _priceDeltaCtrls = {};

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _subtitle = TextEditingController(text: p?.subtitle ?? '');
    _price = TextEditingController(
        text: p == null ? '' : (p.basePrice.centavos / 100).toStringAsFixed(0));
    _category = p?.category ?? CafeCategory.coffee;
    _itemType = p?.itemType ?? ItemType.drink;
    _typeId = p?.typeId ?? widget.presetTypeId;
    _categoryId = p?.categoryId ?? widget.presetCategoryId;
    _available = p?.available ?? true;
    _openPrice = p?.openPrice ?? false;
    _trackInventory = p?.trackInventory ?? true;
    _imageUrl = p?.imageUrl;
    _emojiFallback = (p?.emoji.isNotEmpty ?? false) ? p!.emoji : '☕';
    _modifierGroups = p?.modifierGroups ?? const [];
    _modifierGroupIds = Set<String>.from(
      p?.modifierGroupIds ?? p?.modifierGroups.map((g) => g.id) ?? const [],
    );
    _recipe = (p?.recipe ?? <RecipeLine>[])
        .map((l) => RecipeLine(
            id: l.id,
            inventoryItemId: l.inventoryItemId,
            quantity: l.quantity))
        .toList();
    _adjustments = (p?.modifierAdjustments ?? <ModifierAdjustment>[])
        .map((a) => ModifierAdjustment(
              id: a.id,
              groupId: a.groupId,
              optionId: a.optionId,
              kind: a.kind,
              multiplier: a.multiplier,
              addLines: a.addLines
                  .map((l) => RecipeLine(
                      id: l.id,
                      inventoryItemId: l.inventoryItemId,
                      quantity: l.quantity))
                  .toList(),
            ))
        .toList();
  }

  TextEditingController _qtyCtrl(RecipeLine line) {
    final c = _qtyCtrls[line.id];
    if (c != null) return c;
    return _qtyCtrls[line.id] =
        TextEditingController(text: line.quantity.toStringAsFixed(0));
  }

  TextEditingController _mulCtrl(String key, double initial) {
    final c = _mulCtrls[key];
    if (c != null) return c;
    return _mulCtrls[key] =
        TextEditingController(text: initial.toStringAsFixed(2));
  }

  TextEditingController _priceDeltaCtrl(String key, Money initial) {
    final c = _priceDeltaCtrls[key];
    if (c != null) return c;
    final pesos = initial.centavos / 100.0;
    return _priceDeltaCtrls[key] = TextEditingController(
        text: pesos == 0 ? '' : pesos.toStringAsFixed(0));
  }

  /// Find existing adjustment for a (group, option) — null if none.
  ModifierAdjustment? _adjFor(String groupId, String optionId) {
    return _adjustments
        .where((a) => a.groupId == groupId && a.optionId == optionId)
        .firstOrNull;
  }

  void _setAdjustment({
    required String groupId,
    required String optionId,
    required AdjustmentKind kind,
    double? multiplier,
    Map<String, double>? lineMultipliers,
    List<RecipeLine>? addLines,
    Money? priceDelta,
  }) {
    final i = _adjustments
        .indexWhere((a) => a.groupId == groupId && a.optionId == optionId);
    final adj = ModifierAdjustment(
      id: i >= 0 ? _adjustments[i].id : null,
      groupId: groupId,
      optionId: optionId,
      kind: kind,
      multiplier: multiplier ?? (i >= 0 ? _adjustments[i].multiplier : 1.0),
      lineMultipliers: lineMultipliers ??
          (i >= 0 ? _adjustments[i].lineMultipliers : <String, double>{}),
      addLines: addLines ?? (i >= 0 ? _adjustments[i].addLines : <RecipeLine>[]),
      priceDelta: priceDelta ??
          (i >= 0 ? _adjustments[i].priceDelta : Money.zero),
    );
    setState(() {
      if (i >= 0) {
        _adjustments[i] = adj;
      } else {
        _adjustments.add(adj);
      }
    });
  }

  /// Apply one multiplier to EVERY base ingredient under an option (the quick
  /// "Set all" chips). Also refreshes the per-ingredient ×fields.
  void _setAllLineMul(
      ModifierGroup group, ModifierOption option, double mul) {
    final map = <String, double>{};
    for (final line in _recipe.where((l) => l.inventoryItemId.isNotEmpty)) {
      if ((mul - 1.0).abs() >= 0.001) map[line.inventoryItemId] = mul;
      _mulCtrls['${option.id}_${line.inventoryItemId}']?.text =
          mul == mul.roundToDouble()
              ? mul.toStringAsFixed(0)
              : mul.toStringAsFixed(2);
    }
    _setAdjustment(
      groupId: group.id,
      optionId: option.id,
      kind: AdjustmentKind.multiplier,
      lineMultipliers: map,
    );
  }

  Widget _mulPresetChip(double mul, VoidCallback onTap) {
    final label = mul == 0 ? 'None' : '×${_numStr(mul)}';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        child: Text(label,
            style: YFont.bodyStrong()
                .copyWith(fontSize: 12, color: YColor.brandDeep)),
      ),
    );
  }

  /// Set the multiplier for one base ingredient under one option. ×1 = no
  /// change (we drop it so the override map stays minimal).
  void _setLineMul(ModifierGroup group, ModifierOption option, String itemId,
      double mul) {
    final adj = _adjFor(group.id, option.id);
    final map = Map<String, double>.from(adj?.lineMultipliers ?? const {});
    if ((mul - 1.0).abs() < 0.001) {
      map.remove(itemId);
    } else {
      map[itemId] = mul;
    }
    _setAdjustment(
      groupId: group.id,
      optionId: option.id,
      kind: AdjustmentKind.multiplier,
      lineMultipliers: map,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _price.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    for (final c in _mulCtrls.values) {
      c.dispose();
    }
    for (final c in _priceDeltaCtrls.values) {
      c.dispose();
    }
    _scrollC.dispose();
    super.dispose();
  }

  /// Basics step is complete — name, price, type and category are all set
  /// (everything required except the subtitle).
  bool get _basicsValid =>
      _name.text.trim().isNotEmpty &&
      // Price required (> 0) unless this is a custom-price product.
      (_openPrice || (double.tryParse(_price.text.trim()) ?? 0) > 0) &&
      _typeId != null &&
      _categoryId != null;

  bool get _canSave => _basicsValid && !_saving;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final priceN = double.tryParse(_price.text) ?? 0;
    // Resolve behavior flags from the picked DB ProductType when available,
    // otherwise fall back to the legacy enum on the in-memory CafeItem.
    final catalog = context.read<CatalogStore>();
    final type = catalog.productTypeById(_typeId);
    final cat = catalog.categories
        .where((c) => c.id == _categoryId)
        .firstOrNull;

    // Products inherit their category's picked icon (from the "Pick an icon"
    // modal) when they don't have their own. Image upload is disabled, so
    // every item shows a themed outlined icon consistently across the app.
    // Product icon follows its category's icon (auto), keeping any prior
    // custom icon only as a fallback.
    final resolvedIconName = cat?.iconName ?? widget.initial?.iconName;

    // Upload pending image bytes first so the saved CafeItem already carries
    // the public URL. Failure here aborts the save and surfaces a toast —
    // the parent caller does NOT see a half-saved product.
    String? finalUrl = _imageUrl;
    if (_pendingImageBytes != null) {
      try {
        finalUrl = await catalog.uploadProductImage(_pendingImageBytes!);
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        PushToast.show(context,
            title: 'Image upload failed',
            subtitle: 'Try a different photo or check your connection.',
            leadingIcon: Icons.error_outline);
        return;
      }
    }

    final saved = CafeItem(
      id: widget.initial?.id,
      name: _name.text.trim(),
      subtitle: _subtitle.text.trim(),
      category: _category,
      categoryId: _categoryId,
      categoryName: cat?.name ?? '',
      basePrice: Money.pesos(priceN),
      emoji: _emojiFallback,
      iconName: resolvedIconName,
      imageUrl: finalUrl,
      tag: widget.initial?.tag,
      itemType: _itemType,
      typeId: _typeId,
      typeName: type?.name ?? '',
      // Per-product now — the product keeps its own modifiers + recipe
      // regardless of the type (the type is just a grouping).
      modifierGroups: _modifierGroups,
      modifierGroupIds: _modifierGroupIds.toList(),
      modifierAdjustments: _adjustments,
      available: _available,
      openPrice: _openPrice,
      // No recipe → nothing to deduct, so tracking is forced off. Drop any
      // half-added lines that never got an ingredient picked.
      trackInventory: _cleanRecipe.isNotEmpty && _trackInventory,
      recipe: _cleanRecipe,
      sortOrder: widget.initial?.sortOrder ?? 0,
    );
    if (!mounted) return;
    // Inline editor saves in place; the dialog returns the item to its caller.
    if (widget.embedded) {
      final err = await context.read<CatalogStore>().updateProduct(saved);
      if (!mounted) return;
      setState(() => _saving = false);
      PushToast.show(context,
          title: err == null ? 'Product updated' : 'Could not save',
          subtitle: err ?? saved.name,
          leadingIcon: err == null
              ? Icons.check_circle_outline
              : Icons.error_outline);
    } else {
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
          widget.embedded
              ? _compactHeader(context)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                  child: Row(children: [
                    Text(
                      widget.initial == null ? 'Add Product' : 'Edit Product',
                      style: YFont.titleLG().copyWith(fontSize: 22),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
          _hairline,
          _stepBar(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollC,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0)
                    _section('Product details', [
                      // Icon (auto from category) · Name (wide) · Price.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: YColor.surface1,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: YColor.hairline),
                            ),
                            child: Builder(builder: (_) {
                              // Mirror the chosen category's icon — resolve from
                              // the category's name + icon (so a name-based
                              // category icon still shows), falling back to the
                              // product name when no category is picked.
                              final c = context
                                  .read<AppState>()
                                  .categories
                                  .where((x) => x.id == _categoryId)
                                  .firstOrNull;
                              return NameIconOrEmoji(
                                name: c?.name ?? _name.text,
                                iconName: c?.iconName,
                                iconSize: 32,
                              );
                            }),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: KeyboardAccessoryField(
                              controller: _name,
                              label: 'Name',
                              accessoryLabel: 'NAME',
                              hint: 'e.g., Caramel Macchiato',
                              fillColor: YColor.surface1,
                              borderColor: YColor.hairline,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: _priceSlot()),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Product Type · Category — both dropdowns, blank default.
                      Row(children: [
                        Expanded(child: _typeDropdown()),
                        const SizedBox(width: 10),
                        Expanded(child: _categoryDropdown()),
                      ]),
                      const SizedBox(height: 14),
                      // Subtitle (optional) — below type + category.
                      KeyboardAccessoryField(
                        controller: _subtitle,
                        label: 'Subtitle (optional)',
                        accessoryLabel: 'SUBTITLE',
                        hint: 'Short description shown under the name',
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        onChanged: (_) => setState(() {}),
                      ),
                    ]),
                  if (_step == 1) _modifierGroupsSection(),
                  if (_step == 2) _recipeSection(),
                  if (_step == 3) _optionsSection(),
                ],
              ),
            ),
          ),
          if (!widget.embedded) ...[
            _hairline,
            Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    if (_step > 0)
                      TextButton.icon(
                        onPressed: () => _setStep(_step - 1),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Back'),
                      ),
                    const Spacer(),
                    if (_step < 3)
                      ElevatedButton(
                        // Can't leave Basics until the required fields are set.
                        onPressed: (_step == 0 && !_basicsValid)
                            ? null
                            : () => _setStep(_step + 1),
                        style: _primaryBtnStyle(),
                        child: const Text('Next'),
                      )
                    else
                      ElevatedButton(
                        onPressed: _canSave ? _save : null,
                        style: _primaryBtnStyle(),
                        child: Text(widget.initial == null
                            ? 'Create product'
                            : 'Save changes'),
                      ),
                  ]),
                ),
          ],
        ]);
    if (widget.embedded) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: YColor.surface1),
        child: body,
      );
    }
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 200,
        height: size.height - 120,
        child: body,
      ),
    );
  }

  ButtonStyle _primaryBtnStyle() => ElevatedButton.styleFrom(
        backgroundColor: YColor.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.md)),
      );

  /// Compact live-preview header for the inline (embedded) editor — icon
  /// (category) · name · price · category · Available toggle.
  Widget _compactHeader(BuildContext context) {
    final priceN = double.tryParse(_price.text.trim()) ?? 0;
    final c = context
        .read<AppState>()
        .categories
        .where((x) => x.id == _categoryId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: NameIconOrEmoji(
              name: c?.name ?? _name.text, iconName: c?.iconName, iconSize: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  _name.text.trim().isEmpty
                      ? 'Unnamed product'
                      : _name.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.titleMD().copyWith(fontSize: 18)),
              const SizedBox(height: 3),
              Row(children: [
                Text(
                    _openPrice ? 'Custom price' : '₱${priceN.toStringAsFixed(0)}',
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.brandDeep, fontSize: 13)),
                if (c != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('· ${c.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.caption()),
                  ),
                ],
              ]),
            ],
          ),
        ),
        // Available toggle · Update · Remove — three matched squares.
        _headerSquare(
          icon: _available
              ? Icons.check_circle
              : Icons.visibility_off_outlined,
          label: _available ? 'Available' : 'Hidden',
          onTap: () {
            setState(() => _available = !_available);
            PushToast.show(
              context,
              title: _available ? 'Available' : 'Hidden',
              subtitle: _available
                  ? 'Shows on the Sell menu.'
                  : 'Hidden from the Sell menu.',
              leadingIcon: _available
                  ? Icons.check_circle
                  : Icons.visibility_off_outlined,
            );
          },
          bg: _available ? YColor.brandTint : YColor.surface2,
          fg: _available ? YColor.brandDeep : YColor.inkMuted,
          border: _available
              ? YColor.brand.withValues(alpha: 0.4)
              : YColor.hairline,
        ),
        const SizedBox(width: 8),
        _headerSquare(
          icon: Icons.check,
          label: 'Update',
          onTap: _canSave ? _save : null,
          bg: YColor.brand,
          fg: Colors.white,
        ),
        if (widget.onRemove != null) ...[
          const SizedBox(width: 8),
          _headerSquare(
            icon: Icons.delete_outline,
            label: 'Remove',
            onTap: widget.onRemove,
            bg: YColor.surface2,
            fg: YColor.danger,
            border: YColor.danger.withValues(alpha: 0.4),
          ),
        ],
      ]),
    );
  }

  /// A 64×56 action square (icon over label) for the inline editor header.
  Widget _headerSquare({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color bg,
    required Color fg,
    Color? border,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 64,
          height: 56,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: fg),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.caption().copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  /// Tappable progress header — jump to any step.
  Widget _stepBar() {
    // Inline editor → real tabs (no 1·2·3·4 progress, you jump freely).
    if (widget.embedded) {
      return Row(children: [
        for (var i = 0; i < _stepTitles.length; i++)
          Expanded(child: _tabItem(i)),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  // top ≈ circle centre so the line links the numbers.
                  margin: const EdgeInsets.only(top: 11, left: 10, right: 10),
                  color: i <= _step ? YColor.brand : YColor.hairline,
                ),
              ),
            _stepPill(i),
          ],
        ],
      ),
    );
  }

  Widget _tabItem(int i) {
    final active = i == _step;
    return GestureDetector(
      onTap: () => _setStep(i),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? YColor.brand : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Center(
          child: Text(
            _stepTitles[i],
            style: YFont.bodyStrong().copyWith(
              fontSize: 13.5,
              color: active ? YColor.brand : YColor.inkMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepPill(int i) {
    final active = i == _step;
    final reached = i <= _step;
    return GestureDetector(
      onTap: () => _setStep(i),
      behavior: HitTestBehavior.opaque,
      // Number above the label — compact, centered.
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: reached ? YColor.brand : YColor.surface2,
            shape: BoxShape.circle,
            border:
                Border.all(color: reached ? YColor.brand : YColor.hairline),
          ),
          child: i < _step
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text('${i + 1}',
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 12,
                      color: reached ? Colors.white : YColor.inkMuted)),
        ),
        const SizedBox(height: 3),
        Text(_stepTitles[i],
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? YColor.brandDeep : YColor.inkMuted,
            )),
      ]),
    );
  }

  /// Price field with an inline Custom switch on its label. When Custom is on
  /// the input is hidden and shows "Price is custom — set at checkout".
  Widget _priceSlot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text('Price (₱)', style: YFont.bodyStrong()),
          const Spacer(),
          Text('Custom',
              style: YFont.caption().copyWith(
                  color: _openPrice ? YColor.brand : YColor.inkMuted)),
          const SizedBox(width: 2),
          SizedBox(
            height: 22,
            child: Transform.scale(
              scale: 0.78,
              child: Switch(
                value: _openPrice,
                onChanged: (v) => setState(() => _openPrice = v),
                activeThumbColor: YColor.brand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        if (_openPrice)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.md),
              border: Border.all(color: YColor.hairline),
            ),
            child: Text('Price is custom, set at checkout',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YFont.body().copyWith(color: YColor.inkMuted)),
          )
        else
          KeyboardAccessoryField(
            controller: _price,
            accessoryLabel: 'PRICE',
            hint: '0',
            keyboardType: TextInputType.number,
            formatPreview: (raw) {
              final n = double.tryParse(raw) ?? 0;
              return '₱${n.toStringAsFixed(0)}';
            },
            fillColor: YColor.surface1,
            borderColor: YColor.hairline,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onChanged: (_) => setState(() {}),
          ),
      ],
    );
  }

  /// Step 4 — Options: the behaviour toggles.
  Widget _optionsSection() {
    return _section('Options', [
      _toggleRow(
        value: _available,
        onChanged: (v) => setState(() => _available = v),
        title: 'Available',
        subtitle: _available
            ? 'Shows on the Sell menu.'
            : 'Hidden — sold out / off menu.',
      ),
      const Divider(height: 1, color: YColor.hairline),
      _toggleRow(
        value: _trackInventory && _recipe.isNotEmpty,
        onChanged: (v) => setState(() => _trackInventory = v),
        enabled: _recipe.isNotEmpty,
        title: 'Track inventory',
        subtitle: _recipe.isEmpty
            ? 'Add a recipe (step 3) first — tracking needs ingredients to deduct.'
            : 'Deducts the recipe from stock and blocks the sale when an ingredient runs out.',
      ),
    ]);
  }

  Widget _toggleRow({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: YFont.bodyStrong().copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: YFont.caption()),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: YColor.brand,
        ),
      ]),
    ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            title.toUpperCase(),
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    return Builder(builder: (ctx) {
      final catalog = ctx.watch<CatalogStore>();
      // ONLY the chosen Product Type's categories — empty until a type is
      // picked, so you can't mismatch a category to the wrong type.
      final cats = _typeId == null
          ? const <cat.Category>[]
          : catalog.categoriesForType(_typeId);
      return ThemedDropdown<String>(
        label: 'Category',
        value: _categoryId,
        items: cats.map((c) => c.id).toList(),
        labelOf: (id) {
          final c = cats.where((x) => x.id == id).firstOrNull;
          return c?.name ?? 'Unknown';
        },
        iconOf: (id) {
          final c = cats.where((x) => x.id == id).firstOrNull;
          if (c == null) return Icons.label_outline;
          return iconFromKey(c.iconName) ??
              materialIconForName(c.name) ??
              Icons.label_outline;
        },
        hint: _typeId == null
            ? 'Pick a Product Type first'
            : cats.isEmpty
                ? 'No categories — add one in Maintenance'
                : 'Pick a category',
        onChanged: (v) => setState(() => _categoryId = v),
      );
    });
  }

  Widget _typeDropdown() {
    return Builder(builder: (ctx) {
      final catalog = ctx.watch<CatalogStore>();
      final types = catalog.productTypes;
      return ThemedDropdown<String>(
        label: 'Product type',
        value: _typeId,
        items: types.map((t) => t.id).toList(),
        labelOf: (id) =>
            types.where((t) => t.id == id).firstOrNull?.name ?? 'Unknown',
        iconOf: (id) {
          final t = types.where((x) => x.id == id).firstOrNull;
          return iconFromKey(t?.iconName) ??
              materialIconForName(t?.name ?? '') ??
              Icons.label_outline;
        },
        hint: types.isEmpty
            ? 'Add a type in Maintenance'
            : 'Pick a product type',
        onChanged: (v) => setState(() {
          _typeId = v;
          // Drop the category if it no longer belongs to the new type.
          final ok = v != null &&
              catalog.categoriesForType(v).any((c) => c.id == _categoryId);
          if (!ok) _categoryId = null;
        }),
      );
    });
  }

  /// Toggle chips for which master modifier groups apply to this product
  /// (Size, Temperature, Strength, …). Picking groups here is what makes
  /// them show up on the Sell product detail sheet — without this, the
  /// cashier never sees size pickers.
  Widget _modifierGroupsSection() {
    return Builder(builder: (ctx) {
      final catalog = ctx.watch<CatalogStore>();
      // Per-product: any product can opt into modifier groups (a product
      // "supports modifiers" simply when groups are toggled on here).
      final groups = catalog.modifierGroups;
      if (groups.isEmpty) {
        return _section('Modifiers', [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No modifier groups yet. Add Size / Temperature / Strength in '
              'Maintenance → Modifier groups, then come back to opt this '
              'product in.',
              style: YFont.caption(),
            ),
          ),
        ]);
      }
      // Default / validate the right-pane selection.
      if (_modGroupSel == null || !groups.any((g) => g.id == _modGroupSel)) {
        _modGroupSel = groups.first.id;
      }
      final sel = groups.firstWhere((g) => g.id == _modGroupSel);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Text('MODIFIERS',
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: YColor.brandDeep,
                )),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Tick the groups that apply to this product, then set each '
              'option\'s price on the right (blank = use the default).',
              style: YFont.caption(),
            ),
          ),
          SizedBox(
            height: 360,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(YRadius.lg),
                border: Border.all(color: YColor.hairline),
              ),
              child: Row(children: [
                // Left rail — group checklist.
                SizedBox(
                  width: 190,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(color: YColor.hairline)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final g in groups)
                          _modRailRow(g, g.id == _modGroupSel),
                      ],
                    ),
                  ),
                ),
                // Right pane — selected group's options.
                Expanded(child: _modRightPane(sel)),
              ]),
            ),
          ),
        ],
      );
    });
  }

  void _toggleModGroup(MasterModifierGroup g) {
    setState(() {
      if (_modifierGroupIds.contains(g.id)) {
        _modifierGroupIds.remove(g.id);
        _modifierGroups =
            _modifierGroups.where((m) => m.id != g.id).toList();
      } else {
        _modifierGroupIds.add(g.id);
        _modifierGroups = [
          ..._modifierGroups,
          ModifierGroup(
            id: g.id,
            name: g.name,
            required: g.required,
            defaultIndex: g.defaultIndex,
            options: g.options
                .map((o) => ModifierOption(
                    id: o.id, name: o.name, priceDelta: o.priceDelta))
                .toList(),
          ),
        ];
      }
    });
  }

  Widget _modRailRow(MasterModifierGroup g, bool selected) {
    final on = _modifierGroupIds.contains(g.id);
    final icon = iconFromKey(g.iconName) ??
        materialIconForName(g.name) ??
        Icons.tune_outlined;
    return GestureDetector(
      onTap: () => setState(() => _modGroupSel = g.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? YColor.brandTint : Colors.transparent,
          borderRadius: BorderRadius.circular(YRadius.md),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => _toggleModGroup(g),
            behavior: HitTestBehavior.opaque,
            child: Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: on ? YColor.brand : YColor.inkMuted,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: YColor.brandDeep),
          const SizedBox(width: 6),
          Expanded(
            child: Text(g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YFont.bodyStrong().copyWith(
                  fontSize: 13,
                  color: selected ? YColor.brandDeep : YColor.ink,
                )),
          ),
        ]),
      ),
    );
  }

  Widget _modRightPane(MasterModifierGroup g) {
    final on = _modifierGroupIds.contains(g.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Row(children: [
            Expanded(
              child: Text(g.name,
                  style: YFont.titleMD().copyWith(fontSize: 16)),
            ),
            Text(on ? 'Applied' : 'Off',
                style: YFont.caption().copyWith(
                    color: on ? YColor.brand : YColor.inkMuted)),
            const SizedBox(width: 6),
            Switch(
              value: on,
              onChanged: (_) => _toggleModGroup(g),
              activeThumbColor: YColor.brand,
            ),
          ]),
        ),
        _hairline,
        Expanded(
          child: on
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  children: [
                    for (final o in g.options) _modOptionRow(g, o),
                  ],
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Turn on "${g.name}" to apply it to this product and set '
                      'its option prices.',
                      textAlign: TextAlign.center,
                      style: YFont.caption()
                          .copyWith(color: YColor.inkMuted),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _modOptionRow(MasterModifierGroup g, MasterOption o) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(fontSize: 13)),
              if (o.priceDelta.centavos > 0)
                Text('default +${o.priceDelta.compact}',
                    style:
                        YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 150,
          child: KeyboardAccessoryField(
            controller: _priceDeltaCtrl('${g.id}_${o.id}',
                _adjFor(g.id, o.id)?.priceDelta ?? Money.zero),
            accessoryLabel: '${o.name.toUpperCase()} — EXTRA (₱)',
            hint: '+0',
            keyboardType: TextInputType.number,
            fillColor: YColor.surface1,
            borderColor: YColor.hairline,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            formatPreview: (raw) {
              final n = double.tryParse(raw) ?? 0;
              return n == 0 ? 'default' : '+₱${n.toStringAsFixed(0)}';
            },
            onChanged: (v) {
              final pesos = double.tryParse(v) ?? 0;
              _setAdjustment(
                groupId: g.id,
                optionId: o.id,
                kind: _adjFor(g.id, o.id)?.kind ?? AdjustmentKind.addLines,
                priceDelta: Money((pesos * 100).round()),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _recipeSection() {
    final groups = _modifierGroups;
    if (widget.inventory.isEmpty) {
      return _section('Recipe — auto-deducts on each sale', [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'No inventory items yet. Add some on the Inventory page first, then come back to wire up the recipe.',
            style: YFont.caption(),
          ),
        ),
      ]);
    }

    // No modifiers → just the base recipe editor.
    if (groups.isEmpty) {
      return Container(
        height: 380,
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.lg),
        ),
        child: _baseTab(),
      );
    }

    // With modifiers → Base recipe by default; a top tab per group transitions
    // to that group's rail (options) + per-ingredient multiplier editor.
    final onBase = _recipeTab == 'base' ||
        !groups.any((g) => g.id == _recipeTab);
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Column(children: [
        _recipeTabBar(groups),
        _hairline,
        Expanded(
          child: onBase
              ? _baseTab()
              : _groupRailView(groups.firstWhere((g) => g.id == _recipeTab)),
        ),
      ]),
    );
  }

  /// Top tabs — Base recipe + each modifier group (Size / Temp / …), as pills.
  Widget _recipeTabBar(List<ModifierGroup> groups) {
    Widget tab(String key, String label, IconData icon) {
      final on = key == 'base'
          ? !groups.any((g) => g.id == _recipeTab)
          : _recipeTab == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _recipeTab = key;
            if (key != 'base') {
              final g = groups.firstWhere((g) => g.id == key);
              if (!g.options.any((o) => o.id == _recipeSel) &&
                  g.options.isNotEmpty) {
                _recipeSel = g.options.first.id;
              }
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: on ? YColor.brand : YColor.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: on ? YColor.brand : YColor.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 15, color: on ? Colors.white : YColor.brandDeep),
              const SizedBox(width: 6),
              Text(label,
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 12.5,
                      color: on ? Colors.white : YColor.ink)),
            ]),
          ),
        ),
      );
    }

    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          tab('base', 'Base recipe', Icons.science_outlined),
          for (final g in groups) tab(g.id, g.name, Icons.tune),
        ]),
      ),
    );
  }

  /// One group's rail (its options) + the per-ingredient editor.
  Widget _groupRailView(ModifierGroup group) {
    final sel = group.options.any((o) => o.id == _recipeSel)
        ? _recipeSel
        : (group.options.isNotEmpty ? group.options.first.id : '');
    final option = group.options.where((o) => o.id == sel).firstOrNull;
    return Row(children: [
      SizedBox(
        width: 180,
        child: Container(
          color: YColor.surface1,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
            children: [
              for (final o in group.options)
                _recipeRailRow(
                  label: o.name,
                  icon: Icons.tune,
                  selected: o.id == sel,
                  onTap: () => setState(() => _recipeSel = o.id),
                  customized:
                      _adjFor(group.id, o.id)?.lineMultipliers.isNotEmpty ??
                          false,
                ),
            ],
          ),
        ),
      ),
      Container(width: 0.5, color: YColor.hairline),
      Expanded(
        child: option == null
            ? const SizedBox.shrink()
            : _optionRecipeEditor(group, option),
      ),
    ]);
  }

  Widget _recipeRailRow({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool customized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(YRadius.md),
          ),
          child: Row(children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 13,
                      color: selected ? Colors.white : YColor.ink)),
            ),
            if (customized)
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : YColor.brand,
                  shape: BoxShape.circle,
                ),
              ),
          ]),
        ),
      ),
    );
  }

  String _numStr(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Right pane — per-ingredient multipliers + extra lines for one option.
  Widget _optionRecipeEditor(ModifierGroup group, ModifierOption option) {
    final adj = _adjFor(group.id, option.id);
    final baseLines =
        _recipe.where((l) => l.inventoryItemId.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${group.name} · ${option.name}',
              style: YFont.titleMD().copyWith(fontSize: 16)),
          const SizedBox(height: 2),
          Text(
              'Scale each base ingredient (×1 = no change, ×0 to remove). '
              'Add ingredients in Base recipe.',
              style: YFont.caption()),
          if (baseLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Quick: apply one multiplier to every ingredient at once.
            Row(children: [
              Text('Set all:',
                  style: YFont.caption()
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              for (final p in const [0.0, 1.0, 1.5, 2.0, 3.0])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _mulPresetChip(
                      p, () => _setAllLineMul(group, option, p)),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: baseLines.isEmpty
                ? Center(
                    child: Text('Add base ingredients first (Base recipe).',
                        textAlign: TextAlign.center,
                        style: YFont.caption()))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final line in baseLines)
                        _optionLineRow(group, option, line, adj),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _optionLineRow(ModifierGroup group, ModifierOption option,
      RecipeLine line, ModifierAdjustment? adj) {
    final it = widget.inventory
        .where((i) => i.id == line.inventoryItemId)
        .firstOrNull;
    if (it == null) return const SizedBox.shrink();
    final unit = (it.unitLabel?.trim().isNotEmpty ?? false)
        ? it.unitLabel!.trim()
        : it.unit.label.split(' (').first;
    final mul = adj?.lineMultipliers[line.inventoryItemId] ?? 1.0;
    final result = line.quantity * mul;
    final ctrl = _mulCtrl('${option.id}_${line.inventoryItemId}', mul);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
              materialIconForName(it.name) ?? Icons.inventory_2_outlined,
              size: 17,
              color: YColor.brandDeep),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(fontSize: 13.5)),
              Text('base ${_numStr(line.quantity)} $unit',
                  style: YFont.caption()),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: YFont.bodyStrong().copyWith(fontSize: 13),
            decoration: InputDecoration(
              prefixText: '×',
              isDense: true,
              filled: true,
              fillColor: YColor.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YRadius.md),
                borderSide: const BorderSide(color: YColor.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YRadius.md),
                borderSide: const BorderSide(color: YColor.hairline),
              ),
            ),
            onChanged: (v) => _setLineMul(group, option,
                line.inventoryItemId, double.tryParse(v) ?? 1.0),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: Text('= ${_numStr(result)} $unit',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: YFont.bodyStrong()
                  .copyWith(fontSize: 12.5, color: YColor.brandDeep)),
        ),
      ]),
    );
  }

  Widget _baseTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Caption + Add ingredient anchored right.
          Row(children: [
            Expanded(
              child: Text(
                'Default ingredients used when no modifiers change them',
                style: YFont.caption(),
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (_) {
              // Block adding another line while one is still empty.
              final hasEmpty =
                  _recipe.any((l) => l.inventoryItemId.isEmpty);
              return OutlinedButton.icon(
                onPressed: hasEmpty
                    ? null
                    : () => setState(() {
                          _recipe.add(
                              RecipeLine(inventoryItemId: '', quantity: 1));
                        }),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add ingredient'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: YColor.brand,
                  side: const BorderSide(color: YColor.hairline),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              );
            }),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: _recipe.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: YColor.brandTint.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.science_outlined,
                              size: 26, color: YColor.brandDeep),
                        ),
                        const SizedBox(height: 12),
                        Text('No ingredients yet',
                            style: YFont.bodyStrong()
                                .copyWith(color: YColor.inkMuted)),
                        const SizedBox(height: 3),
                        Text(
                            'Link inventory items so stock auto-deducts on each sale.',
                            textAlign: TextAlign.center,
                            style: YFont.caption()),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      // 1 item → full width, 2 → halves, 3+ → thirds.
                      crossAxisCount: _recipe.length.clamp(1, 3),
                      mainAxisExtent: 84,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _recipe.length,
                    itemBuilder: (_, i) => _recipeLine(i),
                  ),
          ),
        ],
      ),
    );
  }

  /// Searchable ingredient picker — a bottom sheet listing inventory items
  /// (icon · name · stock) with a live search box.
  Widget _recipeLine(int index) {
    final line = _recipe[index];
    final item = widget.inventory
        .where((i) => i.id == line.inventoryItemId)
        .firstOrNull;
    // Full unit name (e.g. "Grams"), or a custom override.
    final unit = item == null
        ? ''
        : ((item.unitLabel?.trim().isNotEmpty ?? false)
            ? item.unitLabel!.trim()
            : item.unit.label.split(' (').first);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Remove anchored top-right.
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                final removed = _recipe.removeAt(index);
                _qtyCtrls.remove(removed.id)?.dispose();
              }),
              child: Text('Remove',
                  style: YFont.caption().copyWith(
                      color: YColor.danger, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 2),
          // Ingredient (icon + name) and quantity on one line.
          Row(children: [
            Expanded(
              child: IngredientSearchField(
                items: widget.inventory,
                selectedId:
                    line.inventoryItemId.isEmpty ? null : line.inventoryItemId,
                onSelect: (id) => setState(() => line.inventoryItemId = id),
              ),
            ),
            const SizedBox(width: 8),
            // Quantity with the unit inside — disabled until an item is picked.
            SizedBox(
              width: 98,
              child: IgnorePointer(
                ignoring: item == null,
                child: Opacity(
                  opacity: item == null ? 0.4 : 1,
                  child: KeyboardAccessoryField(
                    controller: _qtyCtrl(line),
                    accessoryLabel: 'QUANTITY',
                    hint: '0',
                    keyboardType: TextInputType.number,
                    fillColor: YColor.surface2,
                    borderColor: YColor.hairline,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 11),
                    suffix: unit.isEmpty
                        ? null
                        : Center(
                            widthFactor: 1.0,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 2, right: 8),
                              child: Text(unit,
                                  style: YFont.bodyStrong().copyWith(
                                      color: YColor.inkMuted, fontSize: 11.5)),
                            ),
                          ),
                    onChanged: (v) {
                      line.quantity = double.tryParse(v) ?? 0;
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
