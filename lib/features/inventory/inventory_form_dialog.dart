import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart'
    show iconFromKey, materialIconForName;
import '../../design_system/spacing.dart';
import '../../design_system/themed_dropdown.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';
import '../widgets/keyboard_accessory_field.dart';

class InventoryFormDialog extends StatefulWidget {
  const InventoryFormDialog({super.key, this.initial});
  final InventoryItem? initial;

  @override
  State<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends State<InventoryFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _supplier;
  late final TextEditingController _stock;
  late final TextEditingController _threshold;
  late final TextEditingController _cost;
  late final TextEditingController _unitLabel;

  late StockUnit _unit;
  /// FK to public.inventory_categories. The string text [_category] is
  /// kept in sync (denormalized for legacy display); both flow into the
  /// saved row payload.
  String? _categoryId;
  late String _category;
  /// "Will I restock this item?" toggle. When true, low-stock alerts fire
  /// on the Stock page (backed by `low_stock_threshold > 0`). When false,
  /// alerts are silenced — useful for one-off items (rare books, signed
  /// copies, gift items) the owner doesn't plan to reorder.
  ///
  /// Pure UI affordance over `low_stock_threshold`: turning it off forces
  /// threshold = 0 on save; turning it on lets the owner type a real
  /// threshold. No DB column required.
  late bool _restockable;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _sku = TextEditingController(text: i?.sku ?? '');
    _supplier = TextEditingController(text: i?.supplier ?? '');
    _stock = TextEditingController(
        text: i == null ? '' : _fmt(i.currentStock, i.unit));
    _threshold = TextEditingController(
        text: i == null ? '' : _fmt(i.lowStockThreshold, i.unit));
    _cost = TextEditingController(
        text: i == null ? '' : i.costPerUnit.toString());
    _unitLabel = TextEditingController(text: i?.unitLabel ?? '');
    _unit = i?.unit ?? StockUnit.grams;
    _categoryId = i?.categoryId;
    _category = i?.category ?? kInventoryCategories.first;
    // Existing rows: infer restockable from whether a threshold was set.
    // New rows: default ON (ingredients are the common case).
    _restockable = i == null ? true : (i.lowStockThreshold > 0);
  }

  /// What the form shows in labels / previews: the custom override if the
  /// owner typed one, else the preset symbol.
  String get _displaySymbol {
    final override = _unitLabel.text.trim();
    return override.isEmpty ? _unit.symbol : override;
  }

  String _fmt(double v, StockUnit u) {
    final isCount = u == StockUnit.pieces || u == StockUnit.packs;
    return isCount
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _supplier.dispose();
    _stock.dispose();
    _threshold.dispose();
    _cost.dispose();
    _unitLabel.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    final label = _unitLabel.text.trim();
    // Restockable=false zeroes the threshold so low-stock alerts stay silent.
    final threshold = _restockable
        ? (double.tryParse(_threshold.text) ?? 0)
        : 0.0;
    final saved = InventoryItem(
      id: widget.initial?.id,
      name: _name.text.trim(),
      sku: _sku.text.trim(),
      category: _category,
      categoryId: _categoryId,
      unit: _unit,
      unitLabel: label.isEmpty ? null : label,
      currentStock: double.tryParse(_stock.text) ?? 0,
      lowStockThreshold: threshold,
      costPerUnit: double.tryParse(_cost.text) ?? 0,
      supplier: _supplier.text.trim(),
      lastRestockedAt: widget.initial?.lastRestockedAt,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 200,
        height: size.height - 120,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null ? 'Add Inventory Item' : 'Edit Item',
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Item details', [
                    _row(
                      KeyboardAccessoryField(
                        controller: _name,
                        label: 'Name',
                        accessoryLabel: 'NAME',
                        hint: 'e.g., Coffee Beans (House Blend)',
                        onChanged: (_) => setState(() {}),
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      KeyboardAccessoryField(
                        controller: _sku,
                        label: 'SKU',
                        accessoryLabel: 'SKU',
                        hint: 'e.g., COF-001',
                        onChanged: (_) => setState(() {}),
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _row(_categoryDropdown(), _unitDropdown()),
                    const SizedBox(height: 12),
                    KeyboardAccessoryField(
                      controller: _unitLabel,
                      label: 'Custom unit label (optional)',
                      accessoryLabel: 'UNIT LABEL',
                      hint: 'Leave blank to use "${_unit.symbol}". '
                          'Type "shot", "slice", "tray"… to override.',
                      onChanged: (_) => setState(() {}),
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _section('Stock & cost', [
                    // Restockable toggle drives whether low-stock alerts
                    // ever fire for this item. OFF = silent (one-off books,
                    // signed copies, rare items). ON = alerts based on the
                    // threshold field below.
                    Row(children: [
                      Switch(
                        value: _restockable,
                        onChanged: (v) => setState(() => _restockable = v),
                        activeThumbColor: YColor.brand,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _restockable
                                  ? 'Restockable — alert when low'
                                  : 'One-off — no low-stock alerts',
                              style: YFont.bodyStrong()
                                  .copyWith(fontSize: 13),
                            ),
                            Text(
                              _restockable
                                  ? 'Turn off for unique items you don\'t plan to reorder (rare books, signed copies, gifts).'
                                  : 'Turn on when you carry this item regularly so the system warns you to reorder.',
                              style: YFont.caption(),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _row(
                      KeyboardAccessoryField(
                        controller: _stock,
                        label: 'Current stock ($_displaySymbol)',
                        accessoryLabel: 'STOCK',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        formatPreview: (raw) {
                          final n = double.tryParse(raw) ?? 0;
                          return '${_fmt(n, _unit)} $_displaySymbol';
                        },
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      // Threshold field is only enabled when Restockable is
                      // ON — otherwise we force threshold = 0 on save.
                      Opacity(
                        opacity: _restockable ? 1.0 : 0.45,
                        child: IgnorePointer(
                          ignoring: !_restockable,
                          child: KeyboardAccessoryField(
                            controller: _threshold,
                            label:
                                'Low-stock alert at ($_displaySymbol)',
                            accessoryLabel: 'THRESHOLD',
                            hint: _restockable
                                ? '0 (no alert)'
                                : 'Disabled — toggle Restockable on',
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            fillColor: YColor.surface1,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _row(
                      KeyboardAccessoryField(
                        controller: _cost,
                        label: 'Cost per $_displaySymbol (₱)',
                        accessoryLabel: 'COST',
                        hint: '0.00',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        formatPreview: (raw) {
                          final n = double.tryParse(raw) ?? 0;
                          return '₱${n.toStringAsFixed(2)} / $_displaySymbol';
                        },
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      KeyboardAccessoryField(
                        controller: _supplier,
                        label: 'Supplier (optional)',
                        accessoryLabel: 'SUPPLIER',
                        hint: 'e.g., Mountain Roasters',
                        onChanged: (_) => setState(() {}),
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(widget.initial == null
                    ? 'Add item'
                    : 'Save changes'),
              ),
            ]),
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

  Widget _row(Widget a, Widget b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    );
  }

  Widget _categoryDropdown() {
    // Sources from the tenant-owned inventory_categories table (managed in
    // Maintenance → Inventory categories). Each option carries its icon
    // via ThemedDropdown's iconOf hook so the field + menu match the rest
    // of the icon system.
    return Builder(builder: (ctx) {
      final state = ctx.watch<AppState>();
      final cats = state.inventoryCategories;
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
        hint: cats.isEmpty
            ? 'Add a category in Maintenance first'
            : 'Pick a category',
        onChanged: (id) => setState(() {
          _categoryId = id;
          final picked =
              cats.where((c) => c.id == id).firstOrNull;
          if (picked != null) _category = picked.name;
        }),
      );
    });
  }

  Widget _unitDropdown() {
    return _dropdownWrap(
      label: 'Unit',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<StockUnit>(
          value: _unit,
          isExpanded: true,
          items: StockUnit.values
              .map((u) =>
                  DropdownMenuItem(value: u, child: Text(u.label)))
              .toList(),
          onChanged: (v) => setState(() => _unit = v ?? _unit),
        ),
      ),
    );
  }

  Widget _dropdownWrap({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: YFont.bodyStrong().copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: child,
        ),
      ],
    );
  }
}
