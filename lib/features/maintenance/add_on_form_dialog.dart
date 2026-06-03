import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;
import '../../models/inventory.dart';
import '../../models/money.dart';
import '../widgets/keyboard_accessory_field.dart';

class AddOnFormDialog extends StatefulWidget {
  const AddOnFormDialog({
    super.key,
    this.initial,
    required this.inventory,
    required this.categories,
  });
  final AddOn? initial;
  final List<InventoryItem> inventory;
  /// Tenant-owned categories used to populate the per-add-on
  /// "available on" picker. Empty selection = applies everywhere.
  final List<cat.Category> categories;

  @override
  State<AddOnFormDialog> createState() => _AddOnFormDialogState();
}

class _AddOnFormDialogState extends State<AddOnFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _maxQty;
  late List<RecipeLine> _recipe;
  late Set<String> _categoryIds;
  String? _iconName;
  final Map<String, TextEditingController> _qtyCtrls = {};

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _name = TextEditingController(text: a?.name ?? '');
    _iconName = a?.iconName;
    _price = TextEditingController(
        text: a == null ? '' : (a.priceDelta.centavos / 100).toStringAsFixed(0));
    _maxQty = TextEditingController(
        text: a == null || a.maxQuantity == 0 ? '' : a.maxQuantity.toString());
    _recipe = (a?.recipe ?? <RecipeLine>[])
        .map((l) => RecipeLine(
              id: l.id,
              inventoryItemId: l.inventoryItemId,
              quantity: l.quantity,
            ))
        .toList();
    _categoryIds = Set<String>.from(
        a?.applicableCategoryIds ?? <String>{});
  }

  TextEditingController _qtyCtrl(RecipeLine line) {
    final c = _qtyCtrls[line.id];
    if (c != null) return c;
    return _qtyCtrls[line.id] =
        TextEditingController(text: line.quantity.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _maxQty.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    final price = double.tryParse(_price.text) ?? 0;
    final max = int.tryParse(_maxQty.text) ?? 0;
    final saved = AddOn(
      id: widget.initial?.id,
      name: _name.text.trim(),
      emoji: widget.initial?.emoji ?? '',
      iconName: _iconName,
      priceDelta: Money.pesos(price),
      maxQuantity: max,
      recipe: _recipe,
      applicableCategoryIds: _categoryIds,
      sortOrder: widget.initial?.sortOrder ?? 0,
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
                widget.initial == null ? 'Add Add-on' : 'Edit Add-on',
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
                  _section('Add-on details', [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4, bottom: 6),
                                child: Text('Icon', style: YFont.caption()),
                              ),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Name',
                            accessoryLabel: 'NAME',
                            hint: 'e.g., Extra espresso shot',
                            fillColor: YColor.surface1,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _price,
                          label: 'Price (₱)',
                          accessoryLabel: 'PRICE',
                          hint: '0',
                          keyboardType: TextInputType.number,
                          formatPreview: (raw) {
                            final n = double.tryParse(raw) ?? 0;
                            return '+₱${n.toStringAsFixed(0)} each';
                          },
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _maxQty,
                          label: 'Max per order',
                          accessoryLabel: 'MAX QUANTITY',
                          hint: '0 = unlimited',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 18),
                  _section('Available on these categories', [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _categoryIds.isEmpty
                            ? 'Currently shows on ALL products. Pick categories below to limit it (e.g., Coffee only).'
                            : 'Only shows on products in the selected categories.',
                        style: YFont.caption(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.categories.isEmpty)
                      Text(
                        'No categories yet. Add some in Maintenance → Categories first.',
                        style:
                            YFont.caption().copyWith(color: YColor.inkMuted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.categories.map((c) {
                          final selected = _categoryIds.contains(c.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _categoryIds.remove(c.id);
                              } else {
                                _categoryIds.add(c.id);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 130),
                              padding: const EdgeInsets.fromLTRB(
                                  10, 8, 14, 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? YColor.brand
                                    : YColor.surface1,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: selected
                                      ? YColor.brand
                                      : YColor.hairline,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  NameIconOrEmoji(
                                    name: c.name,
                                    iconName: c.iconName,
                                    iconSize: 16,
                                    color: selected
                                        ? Colors.white
                                        : YColor.brandDeep,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    c.name,
                                    style: YFont.bodyStrong().copyWith(
                                      fontSize: 12,
                                      color: selected
                                          ? Colors.white
                                          : YColor.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (_categoryIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _categoryIds.clear()),
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('Show on all categories'),
                          style: TextButton.styleFrom(
                            foregroundColor: YColor.inkMuted,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  _section('Ingredients deducted per add-on', [
                    if (widget.inventory.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'No inventory items yet. Add items on the Inventory page first to wire up deductions.',
                          style: YFont.caption(),
                        ),
                      )
                    else ...[
                      if (_recipe.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'No ingredients yet. Add lines to deduct stock when this add-on is used (or leave empty for a charge-only add-on like "Whipped cream").',
                            style: YFont.caption(),
                          ),
                        )
                      else
                        for (var i = 0; i < _recipe.length; i++)
                          _recipeLine(i),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(YRadius.md)),
                          ),
                        ),
                      ),
                    ],
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
                    ? 'Add add-on'
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
                              child: SizedBox(
                                height: 36,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${it.name} (${it.displayUnit})',
                                    style: YFont.bodyStrong()
                                        .copyWith(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(
                        () => line.inventoryItemId = v ?? line.inventoryItemId),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(unit,
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.inkMuted)),
              ),
            ),
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
