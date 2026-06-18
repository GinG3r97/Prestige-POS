import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';
import '../widgets/numpad_field.dart';

class RestockResult {
  final double quantity;
  final double? newCostPerUnit;
  RestockResult({required this.quantity, this.newCostPerUnit});
}

class StockTakeResult {
  /// Signed delta in the item's unit (negative = remove, positive = add).
  final double delta;
  final StockTakeReason reason;
  StockTakeResult({required this.delta, required this.reason});
}

/// Restock dialog: adds stock and optionally updates cost per unit.
class RestockDialog extends StatefulWidget {
  const RestockDialog({super.key, required this.item});
  final InventoryItem item;

  @override
  State<RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<RestockDialog> {
  final _qty = TextEditingController();
  final _cost = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cost.text = widget.item.costPerUnit > 0
        ? widget.item.costPerUnit.toString()
        : '';
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_qty.text) ?? 0;
    final newStock = widget.item.currentStock + qty;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: YColor.brandTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.add_box_outlined,
              color: YColor.brand, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restock', style: YFont.titleMD()),
              Text(widget.item.name, style: YFont.caption()),
            ],
          ),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NumpadField(
              controller: _qty,
              label: 'Quantity received (${widget.item.displayUnit})',
              title: 'Quantity received',
              hint: '0',
              decimal: false,
              suffix: widget.item.displayUnit,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            NumpadField(
              controller: _cost,
              label:
                  'Cost per ${widget.item.displayUnit} (₱) — optional update',
              title: 'Cost per ${widget.item.displayUnit}',
              hint: widget.item.costPerUnit.toStringAsFixed(2),
              prefix: '₱',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: YColor.brandTint.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Row(children: [
                const Icon(Icons.trending_up,
                    size: 16, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Text(
                  'New stock: ${newStock.toStringAsFixed(0)} ${widget.item.displayUnit}',
                  style: YFont.bodyStrong().copyWith(color: YColor.brandDeep),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: qty > 0
              ? () {
                  final cost = double.tryParse(_cost.text);
                  Navigator.pop(
                    context,
                    RestockResult(
                      quantity: qty,
                      newCostPerUnit:
                          (cost != null && cost > 0) ? cost : null,
                    ),
                  );
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YRadius.md)),
          ),
          child: const Text('Add stock'),
        ),
      ],
    );
  }
}

/// Stock take dialog: adjust stock with a reason (waste, recount, theft, …).
class StockTakeDialog extends StatefulWidget {
  const StockTakeDialog({super.key, required this.item});
  final InventoryItem item;

  @override
  State<StockTakeDialog> createState() => _StockTakeDialogState();
}

class _StockTakeDialogState extends State<StockTakeDialog> {
  final _amount = TextEditingController();
  StockTakeReason _reason = StockTakeReason.recount;
  bool _isAdd = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_amount.text) ?? 0;
    final delta = _isAdd ? qty : -qty;
    final newStock = (widget.item.currentStock + delta).clamp(0, double.infinity);

    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: YColor.surface3,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.tune, color: YColor.brand, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock take', style: YFont.titleMD()),
              Text(widget.item.name, style: YFont.caption()),
            ],
          ),
        ),
      ]),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Direction toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Row(children: [
                _toggle('Remove', !_isAdd, () => setState(() => _isAdd = false),
                    YColor.danger),
                _toggle('Add', _isAdd, () => setState(() => _isAdd = true),
                    YColor.success),
              ]),
            ),
            const SizedBox(height: 12),
            NumpadField(
              controller: _amount,
              label: 'Amount (${widget.item.displayUnit})',
              title: 'Amount',
              hint: '0',
              decimal: false,
              suffix: widget.item.displayUnit,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            // Reason chips
            Text('Reason',
                style: YFont.bodyStrong().copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StockTakeReason.values.map((r) {
                final selected = _reason == r;
                return GestureDetector(
                  onTap: () => setState(() => _reason = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? YColor.brand : YColor.surface2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      r.label,
                      style: YFont.bodyStrong().copyWith(
                        fontSize: 12,
                        color: selected ? Colors.white : YColor.ink,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_isAdd ? YColor.success : YColor.danger)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Row(children: [
                Icon(
                  _isAdd ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: _isAdd ? YColor.success : YColor.danger,
                ),
                const SizedBox(width: 10),
                Text(
                  '${widget.item.currentStock.toStringAsFixed(0)} → ${newStock.toStringAsFixed(0)} ${widget.item.displayUnit}',
                  style: YFont.bodyStrong().copyWith(
                    color: _isAdd ? YColor.success : YColor.danger,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: qty > 0
              ? () => Navigator.pop(
                    context,
                    StockTakeResult(delta: delta, reason: _reason),
                  )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YRadius.md)),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool selected, VoidCallback onTap, Color tone) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tone : Colors.transparent,
            borderRadius: BorderRadius.circular(YRadius.md - 2),
          ),
          child: Text(
            label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 13,
              color: selected ? Colors.white : YColor.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
