import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';
import '../widgets/push_toast.dart';
import 'inventory_form_dialog.dart';
import 'inventory_action_dialogs.dart';

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

enum _Filter { all, low, out }

class _InventoryViewState extends State<InventoryView> {
  _Filter _filter = _Filter.all;
  String? _category;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.inventory;

    // Categories present, ordered by Coffee & Tea → other ingredient
    // buckets → Books / merch → Placeholder (rest alphabetical inside
    // each band).
    int rank(String c) {
      final n = c.toLowerCase();
      if (n.startsWith('coffee')) return 0;
      if (n == 'food' || n.startsWith('food')) return 1;
      if (n.startsWith('placeholder')) return 9;
      return 5;
    }
    final categories = all.map((i) => i.category).toSet().toList()
      ..sort((a, b) {
        final ra = rank(a);
        final rb = rank(b);
        return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
      });
    // No "All" anymore — default-select the first category once we have
    // any. Re-pick if the user's previous choice was removed.
    if (categories.isNotEmpty &&
        (_category == null || !categories.contains(_category))) {
      _category = categories.first;
    }

    final filtered = _applyFilter(all);

    final lowCount = all.where((i) => i.isLowStock && !i.isOutOfStock).length;
    final outCount = all.where((i) => i.isOutOfStock).length;
    final totalValue = all.fold<double>(
        0, (acc, it) => acc + (it.currentStock * it.costPerUnit));

    return Container(
      color: YColor.surface2,
      // Header sits outside the scroll view so it stays pinned at the top
      // while the stat cards + item list scroll beneath it. Mirrors the
      // More page pattern.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: _InvCentered(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inventory',
                            style: YFont.titleLG().copyWith(
                                fontSize: 30, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        Text(
                          '${all.length} items · auto-deducts on each sale',
                          style: YFont.body()
                              .copyWith(color: YColor.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context, state, null),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add item'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: _InvCentered(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // Stat cards
                Row(children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.inventory_2_outlined,
                      label: 'Items',
                      value: '${all.length}',
                      color: YColor.brandDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Low stock',
                      value: '$lowCount',
                      color: lowCount > 0 ? Colors.orange : YColor.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.cancel_outlined,
                      label: 'Out of stock',
                      value: '$outCount',
                      color: outCount > 0 ? YColor.danger : YColor.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.payments_outlined,
                      label: 'Stock value',
                      value: '₱${totalValue.toStringAsFixed(0)}',
                      color: YColor.brand,
                    ),
                  ),
                ]),
                const SizedBox(height: 22),

                // Filter row
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: YColor.surface1,
                    borderRadius: BorderRadius.circular(YRadius.lg),
                    border: Border.all(
                        color: YColor.hairline.withValues(alpha: 0.6)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.search, size: 18),
                          hintText: 'Search by name, SKU, supplier…',
                          hintStyle: YFont.body()
                              .copyWith(color: YColor.inkSubtle),
                          filled: true,
                          fillColor: YColor.surface2,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(YRadius.md),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _filterChip('All', _filter == _Filter.all,
                        () => setState(() => _filter = _Filter.all)),
                    const SizedBox(width: 6),
                    _filterChip(
                      'Low ($lowCount)',
                      _filter == _Filter.low,
                      () => setState(() => _filter = _Filter.low),
                      tone: lowCount > 0 ? Colors.orange : null,
                    ),
                    const SizedBox(width: 6),
                    _filterChip(
                      'Out ($outCount)',
                      _filter == _Filter.out,
                      () => setState(() => _filter = _Filter.out),
                      tone: outCount > 0 ? YColor.danger : null,
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 36,
                    // Removed the "All categories" chip — Stock now always
                    // lands on a real bucket (Coffee & Tea first, then the
                    // rest in their declared sort order).
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final c in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _categoryChip(c, c),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // List
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(36),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: YColor.surface1,
                      borderRadius: BorderRadius.circular(YRadius.lg),
                      border: Border.all(color: YColor.hairline),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 38, color: YColor.inkMuted),
                        const SizedBox(height: 8),
                        Text('No items match.',
                            style: YFont.bodyStrong()),
                        Text(
                          'Try a different search or clear the filter.',
                          style: YFont.caption(),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: YColor.surface1,
                      borderRadius: BorderRadius.circular(YRadius.lg),
                      border: Border.all(
                          color: YColor.hairline.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          _ItemRow(
                            item: filtered[i],
                            onEdit: () =>
                                _openForm(context, state, filtered[i]),
                            onRestock: () =>
                                _openRestock(context, state, filtered[i]),
                            onStockTake: () =>
                                _openStockTake(context, state, filtered[i]),
                            onRemove: () =>
                                _confirmRemove(context, state, filtered[i]),
                          ),
                          if (i != filtered.length - 1)
                            Container(
                              height: 0.5,
                              color: YColor.hairline,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<InventoryItem> _applyFilter(List<InventoryItem> all) {
    var result = List<InventoryItem>.from(all);
    if (_filter == _Filter.low) {
      result = result.where((i) => i.isLowStock && !i.isOutOfStock).toList();
    } else if (_filter == _Filter.out) {
      result = result.where((i) => i.isOutOfStock).toList();
    }
    if (_category != null) {
      result = result.where((i) => i.category == _category).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((i) {
        return i.name.toLowerCase().contains(q) ||
            i.sku.toLowerCase().contains(q) ||
            i.supplier.toLowerCase().contains(q) ||
            i.category.toLowerCase().contains(q);
      }).toList();
    }
    return result;
  }

  Widget _filterChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    Color? tone,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? (tone ?? YColor.brand)
              : (tone == null
                  ? YColor.surface2
                  : tone.withValues(alpha: 0.10)),
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(
            color: selected ? Colors.transparent : YColor.hairline,
          ),
        ),
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(
            fontSize: 12,
            color: selected
                ? Colors.white
                : (tone ?? YColor.ink),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String? value, String label) {
    final selected = _category == value;
    return GestureDetector(
      onTap: () => setState(() => _category = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? YColor.brand : YColor.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(
            fontSize: 12,
            color: selected ? Colors.white : YColor.ink,
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
      BuildContext context, AppState state, InventoryItem? existing) async {
    final saved = await showDialog<InventoryItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InventoryFormDialog(initial: existing),
    );
    if (saved == null || !mounted) return;
    final err = existing == null
        ? await state.addInventoryItem(saved)
        : await state.updateInventoryItem(saved);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: existing == null ? 'Item added' : 'Item updated',
      subtitle: '${saved.name} · ${saved.displayUnit}',
      leadingIcon: Icons.inventory_2,
    );
  }

  Future<void> _openRestock(
      BuildContext context, AppState state, InventoryItem item) async {
    final result = await showDialog<RestockResult>(
      context: context,
      builder: (_) => RestockDialog(item: item),
    );
    if (result == null || !mounted) return;
    final err = await state.restock(item.id, result.quantity,
        newCostPerUnit: result.newCostPerUnit);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not restock',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: 'Restocked',
      subtitle:
          '${item.name} · +${result.quantity.toStringAsFixed(item.unit == StockUnit.pieces || item.unit == StockUnit.packs ? 0 : 1)}${item.displayUnit}',
      leadingIcon: Icons.add_box_outlined,
    );
  }

  Future<void> _openStockTake(
      BuildContext context, AppState state, InventoryItem item) async {
    final result = await showDialog<StockTakeResult>(
      context: context,
      builder: (_) => StockTakeDialog(item: item),
    );
    if (result == null || !mounted) return;
    final err = await state.adjustStock(item.id, result.delta);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not adjust',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: 'Stock adjusted',
      subtitle:
          '${item.name} · ${result.delta >= 0 ? '+' : ''}${result.delta.toStringAsFixed(0)}${item.displayUnit} · ${result.reason.label}',
      leadingIcon: Icons.tune,
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState state, InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text(
            'The item will be removed from this store. Recipes that reference it will need to be updated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await state.removeInventoryItem(item.id);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: 'Item removed',
      subtitle: item.name,
      leadingIcon: Icons.delete_outline,
    );
  }
}

/// Horizontally centers [child] inside the 1100px column. Mirrors the More
/// page pattern — Row + Spacer keeps content top-anchored instead of
/// vertically centered inside the scroll view.
class _InvCentered extends StatelessWidget {
  const _InvCentered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Center (not Spacer+ConstrainedBox+Spacer): Spacers force the box to be
    // measured at its full maxWidth, which overflows on a narrower iPad mini
    // (≈1077pt). Center caps the child to the available width and still
    // centers it on a wide iPad Pro.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: child,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: YFont.caption().copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: YFont.titleLG().copyWith(
                  fontSize: 22,
                  letterSpacing: -0.5,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onEdit,
    required this.onRestock,
    required this.onStockTake,
    required this.onRemove,
  });

  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onRestock;
  final VoidCallback onStockTake;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tone = item.isOutOfStock
        ? YColor.danger
        : item.isLowStock
            ? Colors.orange
            : YColor.success;
    final stockText =
        '${_fmtAmount(item.currentStock, item.unit)}${item.displayUnit}';
    final thresholdText = item.lowStockThreshold > 0
        ? 'Reorder at ${_fmtAmount(item.lowStockThreshold, item.unit)}${item.displayUnit}'
        : 'No reorder threshold';

    // Sold-out rows fade to make the active stock list easier to scan.
    // Still tappable — owners often open the row to add a new shipment.
    final dim = item.isOutOfStock;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        child: Opacity(
          opacity: dim ? 0.55 : 1.0,
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            // Name + meta
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(item.name,
                          style: YFont.bodyStrong().copyWith(fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (item.sku.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: YColor.surface3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.sku,
                          style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 10,
                              color: YColor.inkMuted),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${item.category} · ${item.unit.label}',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            // Stock amount + bar
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      stockText,
                      style: YFont.bodyStrong().copyWith(
                        color: tone,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (item.isLowStock || item.isOutOfStock)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.isOutOfStock ? 'OUT' : 'LOW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: tone,
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.fillRatio,
                      minHeight: 6,
                      backgroundColor: YColor.surface3,
                      valueColor: AlwaysStoppedAnimation(tone),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(thresholdText, style: YFont.caption()),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Cost / value
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${(item.currentStock * item.costPerUnit).toStringAsFixed(0)}',
                    style: YFont.bodyStrong(),
                  ),
                  Text(
                    '₱${item.costPerUnit.toStringAsFixed(2)} / ${item.displayUnit}',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: YColor.inkMuted),
              onSelected: (v) {
                switch (v) {
                  case 'restock':
                    onRestock();
                    break;
                  case 'stocktake':
                    onStockTake();
                    break;
                  case 'edit':
                    onEdit();
                    break;
                  case 'remove':
                    onRemove();
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'restock',
                  child: Row(children: [
                    Icon(Icons.add_box_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Restock'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'stocktake',
                  child: Row(children: [
                    Icon(Icons.tune, size: 16),
                    SizedBox(width: 8),
                    Text('Stock take'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 16, color: YColor.danger),
                    SizedBox(width: 8),
                    Text('Remove',
                        style: TextStyle(color: YColor.danger)),
                  ]),
                ),
              ],
            ),
          ]),
        ),
        ),
      ),
    );
  }

  String _fmtAmount(double amount, StockUnit unit) {
    if (unit == StockUnit.pieces || unit == StockUnit.packs) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(amount % 1 == 0 ? 0 : 1);
  }
}
