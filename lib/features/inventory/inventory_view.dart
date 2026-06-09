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
    // Default lands on "All items" (null category). Only clear a category that
    // was removed so the rail selection stays valid.
    if (_category != null && !categories.contains(_category)) {
      _category = null;
      _filter = _Filter.all;
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
            padding: const EdgeInsets.fromLTRB(24, 14, 16, 12),
            child: Row(
              children: [
                Text('Inventory',
                    style: YFont.titleLG()
                        .copyWith(fontSize: 22, letterSpacing: -0.4)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${all.length} items · ₱${totalValue.toStringAsFixed(0)} value',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        YFont.caption().copyWith(color: YColor.inkMuted),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _openForm(context, state, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left rail: quick filters + categories ──
                SizedBox(
                  width: 212,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: YColor.surface1,
                      border: Border(
                          right: BorderSide(color: YColor.hairline)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
                      children: [
                        _railRow('All items', all.length,
                            icon: Icons.inventory_2_outlined,
                            selected:
                                _category == null && _filter == _Filter.all,
                            onTap: () => setState(() {
                                  _category = null;
                                  _filter = _Filter.all;
                                })),
                        _railRow('Low stock', lowCount,
                            icon: Icons.warning_amber_rounded,
                            tone: Colors.orange,
                            selected: _filter == _Filter.low,
                            onTap: () => setState(() {
                                  _filter = _Filter.low;
                                  _category = null;
                                })),
                        _railRow('Out of stock', outCount,
                            icon: Icons.cancel_outlined,
                            tone: YColor.danger,
                            selected: _filter == _Filter.out,
                            onTap: () => setState(() {
                                  _filter = _Filter.out;
                                  _category = null;
                                })),
                        if (categories.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                            child: Text('CATEGORIES',
                                style: YFont.caption().copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: YColor.inkMuted,
                                )),
                          ),
                          for (final c in categories)
                            _railRow(
                                c, all.where((i) => i.category == c).length,
                                icon: Icons.folder_outlined,
                                selected: _filter == _Filter.all &&
                                    _category == c,
                                onTap: () => setState(() {
                                      _category = c;
                                      _filter = _Filter.all;
                                    })),
                        ],
                      ],
                    ),
                  ),
                ),
                // ── Right pane: search + compact item list ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText: 'Search by name, SKU, supplier…',
                            hintStyle: YFont.body()
                                .copyWith(color: YColor.inkSubtle),
                            filled: true,
                            fillColor: YColor.surface1,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(YRadius.md),
                              borderSide:
                                  const BorderSide(color: YColor.hairline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(YRadius.md),
                              borderSide:
                                  const BorderSide(color: YColor.hairline),
                            ),
                          ),
                        ),
                      ),
                      Container(height: 0.5, color: YColor.hairline),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.inventory_2_outlined,
                                        size: 38, color: YColor.inkMuted),
                                    const SizedBox(height: 8),
                                    Text('No items here',
                                        style: YFont.bodyStrong()),
                                    Text(
                                        'Try another category, search, or add an item.',
                                        style: YFont.caption()),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Container(
                                    height: 0.5,
                                    color: YColor.hairline,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16)),
                                itemBuilder: (_, i) => _ItemRow(
                                  item: filtered[i],
                                  onEdit: () =>
                                      _openForm(context, state, filtered[i]),
                                  onRestock: () => _openRestock(
                                      context, state, filtered[i]),
                                  onStockTake: () => _openStockTake(
                                      context, state, filtered[i]),
                                  onRemove: () => _confirmRemove(
                                      context, state, filtered[i]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
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

  /// Left-rail nav row — icon + label + count, brand highlight when selected.
  Widget _railRow(
    String label,
    int count, {
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    Color? tone,
  }) {
    final accent = tone ?? YColor.brandDeep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? (tone == null
                    ? YColor.brandTint
                    : tone.withValues(alpha: 0.14))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(YRadius.md),
          ),
          child: Row(children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(
                    fontSize: 13,
                    color: selected ? accent : YColor.ink,
                  )),
            ),
            Text('$count',
                style: YFont.caption().copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : YColor.inkMuted,
                )),
          ]),
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
        onTap: () => _showItemActions(context),
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
            // Actions — themed menu, Edit + Remove only
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: YColor.inkMuted),
              color: YColor.surface1,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YRadius.md),
                side: const BorderSide(color: YColor.hairline),
              ),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'remove') onRemove();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined,
                        size: 18, color: YColor.brandDeep),
                    const SizedBox(width: 10),
                    Text('Edit', style: YFont.bodyStrong()),
                  ]),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(children: [
                    const Icon(Icons.delete_outline,
                        size: 18, color: YColor.danger),
                    const SizedBox(width: 10),
                    Text('Remove',
                        style:
                            YFont.bodyStrong().copyWith(color: YColor.danger)),
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

  /// Tapping a row asks what to do with the stock: Restock or Stock take.
  void _showItemActions(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined,
                    color: YColor.brandDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.name,
                      style: YFont.titleMD(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            Container(height: 0.5, color: YColor.hairline),
            _actionTile(
              context,
              Icons.add_box_outlined,
              'Restock',
              'Add new stock you received',
              () {
                Navigator.of(context).pop();
                onRestock();
              },
            ),
            Container(height: 0.5, color: YColor.hairline),
            _actionTile(
              context,
              Icons.fact_check_outlined,
              'Stock take',
              'Count and correct the on-hand quantity',
              () {
                Navigator.of(context).pop();
                onStockTake();
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(YRadius.md),
            ),
            child: Icon(icon, size: 20, color: YColor.brandDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YFont.bodyStrong()),
                const SizedBox(height: 2),
                Text(subtitle, style: YFont.caption()),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: YColor.inkMuted, size: 18),
        ]),
      ),
    );
  }
}
