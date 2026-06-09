import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
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
    final products = state.products;
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
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
                    child: Text('Products',
                        style: YFont.titleLG().copyWith(fontSize: 22)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(children: [
                      Expanded(child: _categoryFilterDropdown(state)),
                      const SizedBox(width: 8),
                      Expanded(child: _statusFilterDropdown()),
                    ]),
                  ),
                  Container(height: 0.5, color: YColor.hairline),
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
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Container(
                                height: 0.5, color: YColor.hairline),
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
                    inventory: state.inventory,
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

  Widget _categoryFilterDropdown(AppState state) {
    final usedIds = state.products
        .map((p) => p.categoryId)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
    final cats = state.categories
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
    return Center(
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
              style: YFont.titleMD().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 4),
          Text('Choose one on the left to view its recipe and details',
              style: YFont.caption()),
        ],
      ),
    );
  }

  Future<void> _openForm(
      BuildContext context, AppState state, CafeItem? existing) async {
    final saved = await showDialog<CafeItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(
        initial: existing,
        inventory: state.inventory,
      ),
    );
    if (saved == null || !mounted) return;
    final err = existing == null
        ? await state.addProduct(saved)
        : await state.updateProduct(saved);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    if (existing == null) {
      final fresh = state.products.lastOrNull;
      setState(() => _selectedId = fresh?.id ?? saved.id);
    }
    // Pick the freshest record so toast image reflects what was saved
    // (uploaded photo URLs only exist after the server roundtrip).
    final fresh = state.products
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
    final err = await state.removeProduct(product.id);
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

// ───── Detail pane ─────

class _ProductDetailPane extends StatelessWidget {
  const _ProductDetailPane({
    required this.product,
    required this.inventory,
    required this.onEdit,
    required this.onToggleAvailability,
    required this.onToggleTracking,
    required this.onRemove,
  });

  final CafeItem product;
  final List<InventoryItem> inventory;
  final VoidCallback onEdit;
  final VoidCallback onToggleAvailability;
  final VoidCallback onToggleTracking;
  final VoidCallback onRemove;

  InventoryItem? _findItem(String id) =>
      inventory.where((i) => i.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView is INSIDE the ConstrainedBox (not the other way
    // around) so the scroll view inherits a bounded height from the parent
    // Expanded slot. With a bounded height the Column inside anchors to
    // the top of the viewport — there's no infinite vertical space for
    // Center / Align to vertically centre the content.
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [YColor.brandTint, YColor.surface1],
                  ),
                  borderRadius: BorderRadius.circular(YRadius.lg),
                  border: Border.all(
                      color: YColor.hairline.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  ProductVisual(
                    imageUrl: product.imageUrl,
                    name: product.name,
                    iconName: product.iconName,
                    size: 84,
                    iconSize: 44,
                    borderRadius: 20,
                    tintBackground: false,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            style: YFont.titleLG().copyWith(
                                fontSize: 26, letterSpacing: -0.4)),
                        const SizedBox(height: 4),
                        Text(product.subtitle,
                            style: YFont.body()
                                .copyWith(color: YColor.inkMuted)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: YColor.brand,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              product.basePrice.formatted,
                              style: YFont.bodyStrong()
                                  .copyWith(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: YColor.surface1,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              product.categoryName.isNotEmpty
                                  ? product.categoryName
                                  : product.category.title,
                              style: YFont.caption()
                                  .copyWith(color: YColor.brandDeep),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildableChip(context, product),
                        ]),
                      ],
                    ),
                  ),
                  Switch(
                    value: product.available,
                    onChanged: (_) => onToggleAvailability(),
                    activeThumbColor: YColor.brand,
                  ),
                ]),
              ),

              const SizedBox(height: 18),

              // Inventory tracking
              Builder(builder: (context) {
                final globalOn =
                    context.watch<AppState>().inventoryTrackingEnabled;
                final on = product.trackInventory;
                return _Card(
                  title: 'INVENTORY',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Track ingredients',
                                  style: YFont.bodyStrong()),
                              const SizedBox(height: 2),
                              Text(
                                on
                                    ? 'Deducts the recipe from stock and stops the sale when an ingredient runs out.'
                                    : 'Sells freely — the recipe is not deducted from stock.',
                                style: YFont.caption(),
                              ),
                              if (on && !globalOn) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Store inventory tracking is OFF, so nothing is deducted right now.',
                                  style: YFont.caption()
                                      .copyWith(color: YColor.brandDeep),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: on,
                          onChanged: (_) => onToggleTracking(),
                          activeThumbColor: YColor.brand,
                        ),
                      ]),
                    ),
                  ],
                );
              }),

              const SizedBox(height: 18),

              // Recipe
              _Card(
                title: 'BASE RECIPE',
                icon: Icons.menu_book_outlined,
                children: product.recipe.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No recipe set. Edit the product to link inventory items so stock auto-deducts on each sale.',
                            style: YFont.caption(),
                          ),
                        ),
                      ]
                    : [
                        for (var i = 0; i < product.recipe.length; i++) ...[
                          _RecipeRow(
                            line: product.recipe[i],
                            item: _findItem(product.recipe[i].inventoryItemId),
                          ),
                          if (i != product.recipe.length - 1)
                            Container(
                                height: 0.5,
                                color: YColor.hairline,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16)),
                        ],
                      ],
              ),

              if (product.modifierAdjustments.isNotEmpty) ...[
                const SizedBox(height: 18),
                _Card(
                  title: 'PER-OPTION ADJUSTMENTS',
                  icon: Icons.tune,
                  children: [
                    for (var i = 0;
                        i < product.modifierAdjustments.length;
                        i++) ...[
                      _AdjustmentRow(
                        adjustment: product.modifierAdjustments[i],
                        product: product,
                        findItem: _findItem,
                      ),
                      if (i != product.modifierAdjustments.length - 1)
                        Container(
                            height: 0.5,
                            color: YColor.hairline,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 16)),
                    ],
                  ],
                ),
              ],


              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: YColor.danger,
                        side: const BorderSide(color: YColor.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit product'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YColor.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Icon(icon, size: 14, color: YColor.brandDeep),
              const SizedBox(width: 8),
              Text(
                title,
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: YColor.brandDeep,
                ),
              ),
            ]),
          ),
          Container(
              height: 0.5,
              color: YColor.hairline,
              margin: const EdgeInsets.symmetric(horizontal: 16)),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.line, required this.item});
  final RecipeLine line;
  final InventoryItem? item;

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const Icon(Icons.error_outline,
              size: 16, color: YColor.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Missing inventory item',
              style: YFont.bodyStrong()
                  .copyWith(color: YColor.danger, fontSize: 13),
            ),
          ),
          Text(line.quantity.toStringAsFixed(0),
              style: YFont.bodyStrong()),
        ]),
      );
    }
    final cost = line.quantity * item!.costPerUnit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_iconFor(item!.unit),
              size: 16, color: YColor.brandDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item!.name, style: YFont.bodyStrong()),
              Text(item!.category, style: YFont.caption()),
            ],
          ),
        ),
        Text(
          '${line.quantity.toStringAsFixed(0)}${item!.displayUnit}',
          style: YFont.bodyStrong().copyWith(color: YColor.brand),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            '₱${cost.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: YFont.caption(),
          ),
        ),
      ]),
    );
  }

  IconData _iconFor(StockUnit u) {
    return switch (u) {
      StockUnit.grams || StockUnit.kilograms => Icons.scale,
      StockUnit.milliliters || StockUnit.liters =>
        Icons.local_drink_outlined,
      StockUnit.pieces || StockUnit.packs => Icons.layers_outlined,
    };
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.adjustment,
    required this.product,
    required this.findItem,
  });
  final ModifierAdjustment adjustment;
  final CafeItem product;
  final InventoryItem? Function(String id) findItem;

  @override
  Widget build(BuildContext context) {
    final group = product.modifierGroups
        .where((g) => g.id == adjustment.groupId)
        .firstOrNull;
    final option = group?.options
        .where((o) => o.id == adjustment.optionId)
        .firstOrNull;
    final groupName = group?.name ?? '?';
    final optionName = option?.name ?? '?';

    final isMul = adjustment.kind == AdjustmentKind.multiplier;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: YColor.surface3,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$groupName · $optionName',
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: YColor.brandDeep,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isMul
                ? '× ${adjustment.multiplier.toStringAsFixed(2)} on all base lines'
                : adjustment.addLines.map((l) {
                    final it = findItem(l.inventoryItemId);
                    return '+${l.quantity.toStringAsFixed(0)}${it?.displayUnit ?? ''} ${it?.name ?? '?'}';
                  }).join(' · '),
            style: YFont.body().copyWith(fontSize: 13),
          ),
        ),
        // Per-option price bump pill — shows the +₱ charge when this
        // option is picked. Hidden when zero so rows without a price
        // override stay clean.
        if (adjustment.priceDelta.centavos > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: YColor.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '+${adjustment.priceDelta.formatted}',
              style: YFont.bodyStrong().copyWith(
                fontSize: 12,
                color: YColor.brand,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.isMul, required this.onSelect});
  final bool isMul;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg('Multiplier', isMul, () => onSelect(true)),
        _seg('Add lines', !isMul, () => onSelect(false)),
      ]),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? YColor.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(
            fontSize: 11,
            color: selected ? Colors.white : YColor.inkMuted,
          ),
        ),
      ),
    );
  }
}

// ───── Form dialog ─────

/// Opens the full Product editor to ADD a product, pre-selecting
/// [presetTypeId] / [presetCategoryId]. Persists via addProduct. Reusable from
/// the Sell "arrange mode" + box.
Future<void> showProductEditor(BuildContext context,
    {String? presetTypeId, String? presetCategoryId}) async {
  final state = context.read<AppState>();
  final saved = await showDialog<CafeItem>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProductFormDialog(
      inventory: state.inventory,
      presetTypeId: presetTypeId,
      presetCategoryId: presetCategoryId,
    ),
  );
  if (saved == null || !context.mounted) return;
  final err = await state.addProduct(saved);
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
  final result =
      await showDialog<({String name, int priceCents, bool openPrice})>(
    context: context,
    builder: (_) => _ProductQuickEditDialog(item: item),
  );
  if (result == null || !context.mounted) return;
  final state = context.read<AppState>();
  item.name = result.name;
  item.basePrice = Money(result.priceCents);
  item.openPrice = result.openPrice;
  final err = await state.updateProduct(item);
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
  late final TextEditingController _price;
  late bool _openPrice;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _price = TextEditingController(
        text: (widget.item.basePrice.centavos / 100).toStringAsFixed(0));
    _openPrice = widget.item.openPrice;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImg =
        widget.item.imageUrl != null && widget.item.imageUrl!.isNotEmpty;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Quick edit', style: YFont.titleMD()),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Locked image preview — full photo editing stays on the Products
            // page for now.
            Row(children: [
              Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: YColor.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: YColor.hairline),
                ),
                child: hasImg
                    ? Image.network(widget.item.imageUrl!,
                        fit: BoxFit.cover,
                        width: 48,
                        height: 48,
                        cacheWidth: 144,
                        cacheHeight: 144,
                        errorBuilder: (_, __, ___) => NameIconOrEmoji(
                            name: widget.item.name,
                            iconName: widget.item.iconName))
                    : NameIconOrEmoji(
                        name: widget.item.name,
                        iconName: widget.item.iconName),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  const Icon(Icons.lock_outline,
                      size: 13, color: YColor.inkMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Photo editing is on the Products page for now.',
                        style:
                            YFont.caption().copyWith(color: YColor.inkMuted)),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
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
            KeyboardAccessoryField(
              controller: _price,
              label: 'Price (₱)',
              accessoryLabel: 'PRICE',
              hint: '0',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyInputFormatters,
              fillColor: YColor.surface2,
              borderColor: YColor.hairline,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Switch(
                value: _openPrice,
                onChanged: (v) => setState(() => _openPrice = v),
                activeThumbColor: YColor.brand,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Custom price — cashier types the price at checkout',
                  style: YFont.caption(),
                ),
              ),
            ]),
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
                  final pesos = double.tryParse(_price.text.trim()) ?? 0;
                  Navigator.of(context).pop((
                    name: _name.text.trim(),
                    priceCents: Money.pesos(pesos).centavos,
                    openPrice: _openPrice,
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

  void _removeAdjustment(String groupId, String optionId) {
    setState(() {
      _adjustments.removeWhere(
          (a) => a.groupId == groupId && a.optionId == optionId);
    });
  }

  /// Compute the resulting recipe for a single (group, option) on top of base.
  /// Used for the live preview under each option.
  List<({String name, double qty, String unit})> _previewFor(
    ModifierGroup group,
    ModifierOption option,
  ) {
    final adj = _adjFor(group.id, option.id);
    var multiplier = 1.0;
    final extras = <RecipeLine>[];
    if (adj != null) {
      if (adj.kind == AdjustmentKind.multiplier) {
        multiplier = adj.multiplier;
      } else {
        extras.addAll(adj.addLines);
      }
    }
    final lines = <({String name, double qty, String unit})>[];
    for (final l in _recipe) {
      final it = widget.inventory
          .where((i) => i.id == l.inventoryItemId)
          .firstOrNull;
      if (it == null) continue;
      lines.add((
        name: it.name,
        qty: l.quantity * multiplier,
        unit: it.displayUnit,
      ));
    }
    for (final l in extras) {
      final it = widget.inventory
          .where((i) => i.id == l.inventoryItemId)
          .firstOrNull;
      if (it == null) continue;
      lines.add((
        name: it.name,
        qty: l.quantity,
        unit: it.displayUnit,
      ));
    }
    return lines;
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
    final state = context.read<AppState>();
    final type = state.productTypeById(_typeId);
    final cat = state.categories
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
        finalUrl = await state.uploadProductImage(_pendingImageBytes!);
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
      // No recipe → nothing to deduct, so tracking is forced off.
      trackInventory: _recipe.isNotEmpty && _trackInventory,
      recipe: _recipe,
      sortOrder: widget.initial?.sortOrder ?? 0,
    );
    if (!mounted) return;
    // Inline editor saves in place; the dialog returns the item to its caller.
    if (widget.embedded) {
      final err = await context.read<AppState>().updateProduct(saved);
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
          Container(height: 0.5, color: YColor.hairline),
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
          Container(height: 0.5, color: YColor.hairline),
          widget.embedded
              ? _embeddedFooter(context)
              : Padding(
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
        Text(_available ? 'Available' : 'Hidden',
            style: YFont.caption().copyWith(
                color: _available ? YColor.brand : YColor.inkMuted)),
        Switch(
          value: _available,
          onChanged: (v) => setState(() => _available = v),
          activeThumbColor: YColor.brand,
        ),
      ]),
    );
  }

  Widget _embeddedFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        if (widget.onRemove != null)
          OutlinedButton.icon(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: YColor.danger),
            label: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: YColor.danger.withValues(alpha: 0.4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _canSave ? _save : null,
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Update'),
          style: _primaryBtnStyle(),
        ),
      ]),
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
      final state = ctx.watch<AppState>();
      // ONLY the chosen Product Type's categories — empty until a type is
      // picked, so you can't mismatch a category to the wrong type.
      final cats = _typeId == null
          ? const <cat.Category>[]
          : state.categoriesForType(_typeId);
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
      final state = ctx.watch<AppState>();
      final types = state.productTypes;
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
              state.categoriesForType(v).any((c) => c.id == _categoryId);
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
      final state = ctx.watch<AppState>();
      // Per-product: any product can opt into modifier groups (a product
      // "supports modifiers" simply when groups are toggled on here).
      final groups = state.modifierGroups;
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
        Container(height: 0.5, color: YColor.hairline),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            'RECIPE — AUTO-DEDUCTS ON EACH SALE',
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            ),
          ),
        ),
        DefaultTabController(
          length: 1 + groups.length,
          child: Container(
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: YColor.brand,
                      borderRadius: BorderRadius.circular(YRadius.md),
                    ),
                    indicatorPadding:
                        const EdgeInsets.symmetric(vertical: 4),
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: YColor.ink,
                    labelStyle: YFont.bodyStrong().copyWith(fontSize: 13),
                    unselectedLabelStyle:
                        YFont.bodyStrong().copyWith(fontSize: 13),
                    tabs: [
                      const Tab(text: 'Base'),
                      ...groups.map((g) => Tab(text: g.name)),
                    ],
                  ),
                ),
                Container(
                  height: 0.5,
                  color: YColor.hairline.withValues(alpha: 0.6),
                  margin: const EdgeInsets.only(top: 8),
                ),
                SizedBox(
                  // tall-ish so the editor has room
                  height: 360,
                  child: TabBarView(
                    children: [
                      _baseTab(),
                      ...groups.map(_groupTab),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _baseTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default ingredients used when no modifiers change them',
            style: YFont.caption(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < _recipe.length; i++)
                    _recipeLine(i),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _recipe.add(RecipeLine(
                inventoryItemId: widget.inventory.first.id,
                quantity: 1,
              ));
            }),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add ingredient'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.brand,
              side: const BorderSide(color: YColor.hairline),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTab(ModifierGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set how each ${group.name.toLowerCase()} option changes the recipe',
            style: YFont.caption(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: group.options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  _buildOptionCard(group, group.options[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(ModifierGroup group, ModifierOption option) {
    final adj = _adjFor(group.id, option.id);
    final isMul = adj == null || adj.kind == AdjustmentKind.multiplier;
    final mul = adj?.multiplier ?? 1.0;
    final preview = _previewFor(group, option);
    final hasCustom = adj != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(
          color: hasCustom
              ? YColor.brand.withValues(alpha: 0.6)
              : YColor.hairline,
          width: hasCustom ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                option.name,
                style: YFont.bodyStrong()
                    .copyWith(fontSize: 13, color: YColor.brandDeep),
              ),
            ),
            if (option.priceDelta.centavos > 0) ...[
              const SizedBox(width: 6),
              Text('+${option.priceDelta.compact}',
                  style: YFont.caption()),
            ],
            const Spacer(),
            // Mode toggle pill
            _ModeToggle(
              isMul: isMul,
              onSelect: (m) {
                _setAdjustment(
                  groupId: group.id,
                  optionId: option.id,
                  kind: m
                      ? AdjustmentKind.multiplier
                      : AdjustmentKind.addLines,
                  multiplier: m ? mul : 1.0,
                  addLines: m
                      ? const []
                      : (adj?.addLines.toList() ?? <RecipeLine>[]),
                );
              },
            ),
            if (hasCustom) ...[
              const SizedBox(width: 6),
              IconButton(
                iconSize: 16,
                tooltip: 'Use base recipe as-is',
                onPressed: () =>
                    _removeAdjustment(group.id, option.id),
                icon: const Icon(Icons.refresh,
                    color: YColor.inkMuted),
              ),
            ],
          ]),
          const SizedBox(height: 10),

          // (Per-option price lives in the Modifiers step now — this card is
          // recipe-only.)

          // Body — recipe behaviour. Multiplier scales all base lines,
          // addLines tacks on extras.
          if (isMul)
            Row(children: [
              SizedBox(
                width: 110,
                child: KeyboardAccessoryField(
                  controller: _mulCtrl(
                      '${group.id}_${option.id}', mul),
                  accessoryLabel: '${option.name.toUpperCase()} MULTIPLIER',
                  hint: '1.00',
                  keyboardType: TextInputType.number,
                  fillColor: YColor.surface2,
                  borderColor: YColor.hairline,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  onChanged: (v) {
                    final n = double.tryParse(v) ?? 1.0;
                    _setAdjustment(
                      groupId: group.id,
                      optionId: option.id,
                      kind: AdjustmentKind.multiplier,
                      multiplier: n,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              const Text('×', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(child: _previewBox(preview)),
            ])
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (adj.addLines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No extra ingredients yet. Add lines to deduct beyond the base.',
                      style: YFont.caption(),
                    ),
                  )
                else
                  for (var i = 0; i < adj.addLines.length; i++)
                    _addLineEditor(group, option, adj, i),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final lines =
                          List<RecipeLine>.from(adj.addLines);
                      lines.add(RecipeLine(
                        inventoryItemId: widget.inventory.first.id,
                        quantity: 1,
                      ));
                      _setAdjustment(
                        groupId: group.id,
                        optionId: option.id,
                        kind: AdjustmentKind.addLines,
                        addLines: lines,
                      );
                    },
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add ingredient'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: YColor.brand,
                      side: const BorderSide(color: YColor.hairline),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _previewBox(preview),
              ],
            ),
        ],
      ),
    );
  }

  Widget _previewBox(
      List<({String name, double qty, String unit})> preview) {
    if (preview.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
        ),
        child: Text('No deductions for this option',
            style: YFont.caption()),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result',
              style: YFont.caption().copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: YColor.brandDeep,
              )),
          const SizedBox(height: 4),
          for (final p in preview)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Text('• ${p.name}', style: YFont.caption()),
                const Spacer(),
                Text(
                  '${_fmtQty(p.qty)} ${p.unit}',
                  style: YFont.bodyStrong()
                      .copyWith(fontSize: 12, color: YColor.brand),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  String _fmtQty(double n) {
    return n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
  }

  Widget _addLineEditor(
    ModifierGroup group,
    ModifierOption option,
    ModifierAdjustment adj,
    int idx,
  ) {
    final line = adj.addLines[idx];
    final item = widget.inventory
        .where((i) => i.id == line.inventoryItemId)
        .firstOrNull;
    final unit = item?.displayUnit ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: YColor.surface2,
                  borderRadius: BorderRadius.circular(YRadius.md),
                  border: Border.all(color: YColor.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: line.inventoryItemId,
                    isExpanded: true,
                    itemHeight: null,
                    items: widget.inventory
                        .map((it) => DropdownMenuItem(
                              value: it.id,
                              child: _ingredientMenuRow(
                                  '${it.name} (${it.displayUnit})'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final lines = adj.addLines
                          .map((l) => l.id == line.id
                              ? RecipeLine(
                                  id: l.id,
                                  inventoryItemId: v,
                                  quantity: l.quantity)
                              : l)
                          .toList();
                      _setAdjustment(
                        groupId: group.id,
                        optionId: option.id,
                        kind: AdjustmentKind.addLines,
                        addLines: lines,
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: KeyboardAccessoryField(
                controller: _qtyCtrl(line),
                accessoryLabel: 'QUANTITY',
                hint: '0',
                keyboardType: TextInputType.number,
                fillColor: YColor.surface2,
                borderColor: YColor.hairline,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
                onChanged: (v) {
                  final n = double.tryParse(v) ?? 0;
                  final lines = adj.addLines
                      .map((l) => l.id == line.id
                          ? RecipeLine(
                              id: l.id,
                              inventoryItemId: l.inventoryItemId,
                              quantity: n)
                          : l)
                      .toList();
                  _setAdjustment(
                    groupId: group.id,
                    optionId: option.id,
                    kind: AdjustmentKind.addLines,
                    addLines: lines,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(unit,
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.inkMuted)),
              ),
            ),
            IconButton(
              iconSize: 18,
              onPressed: () {
                final lines = adj.addLines
                    .where((l) => l.id != line.id)
                    .toList();
                _qtyCtrls.remove(line.id)?.dispose();
                _setAdjustment(
                  groupId: group.id,
                  optionId: option.id,
                  kind: AdjustmentKind.addLines,
                  addLines: lines,
                );
              },
              icon: const Icon(Icons.delete_outline,
                  color: YColor.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  // Shared tight (~36px) menu row for the ingredient-picker dropdowns.
  // Kept here (not in design_system) because it's only used by the recipe
  // sub-rows in this dialog.
  Widget _ingredientMenuRow(String label) {
    return SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _recipeLine(int index) {
    final line = _recipe[index];
    final item = widget.inventory
        .where((i) => i.id == line.inventoryItemId)
        .firstOrNull;
    final unit = item?.displayUnit ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inventory item dropdown
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: YColor.surface1,
                  borderRadius: BorderRadius.circular(YRadius.md),
                  border: Border.all(color: YColor.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: line.inventoryItemId,
                    isExpanded: true,
                    itemHeight: null,
                    items: widget.inventory
                        .map((it) => DropdownMenuItem(
                              value: it.id,
                              child: _ingredientMenuRow(
                                  '${it.name} (${it.displayUnit})'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(
                        () => line.inventoryItemId = v ?? line.inventoryItemId),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Quantity
            SizedBox(
              width: 130,
              child: KeyboardAccessoryField(
                controller: _qtyCtrl(line),
                accessoryLabel: 'QUANTITY',
                hint: '0',
                keyboardType: TextInputType.number,
                fillColor: YColor.surface1,
                borderColor: YColor.hairline,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                onChanged: (v) {
                  line.quantity = double.tryParse(v) ?? 0;
                  setState(() {});
                },
              ),
            ),
            // Unit display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(unit,
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.inkMuted)),
              ),
            ),
            // Remove
            IconButton(
              iconSize: 18,
              onPressed: () => setState(() {
                final removed = _recipe.removeAt(index);
                _qtyCtrls.remove(removed.id)?.dispose();
              }),
              icon: const Icon(Icons.delete_outline,
                  color: YColor.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header chip showing how many of a product can be made from current
/// inventory ("Makes 12") or "Out of stock" when an ingredient is short.
/// Hidden for products that don't draw down stock (no recipe / Service).
Widget _buildableChip(BuildContext context, CafeItem product) {
  final n = context.watch<AppState>().buildableCount(product);
  if (n >= AppState.kUnlimitedBuild) return const SizedBox.shrink();
  final out = n <= 0;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: out ? YColor.dangerSoft : YColor.successSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(out ? Icons.error_outline : Icons.inventory_2_outlined,
          size: 12, color: out ? YColor.danger : YColor.success),
      const SizedBox(width: 4),
      Text(out ? 'Out of stock' : 'Makes $n',
          style: YFont.caption().copyWith(
              color: out ? YColor.danger : YColor.success,
              fontWeight: FontWeight.w700)),
    ]),
  );
}
