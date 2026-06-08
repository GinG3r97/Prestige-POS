import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/cart.dart';
import '../../models/catalog.dart';
import '../../models/money.dart';
import '../auth/otp_numpad.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

class ProductDetailSheet extends StatefulWidget {
  const ProductDetailSheet({super.key, required this.item, this.editLine});
  final CafeItem item;

  /// When set, the sheet edits this existing cart line — it pre-fills the
  /// line's choices and replaces it on save instead of adding a new line.
  final CartLine? editLine;

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  final Map<String, String> selections = {};
  final Map<String, int> addOnQuantities = {};
  int quantity = 1;
  String notes = '';
  final TextEditingController _notesC = TextEditingController();

  /// Raw whole-peso digits typed on the numpad for a Custom-price product.
  String _customPrice = '';
  int get _customPriceCents => (int.tryParse(_customPrice) ?? 0) * 100;

  @override
  void initState() {
    super.initState();
    for (final g in widget.item.modifierGroups) {
      if (g.required && g.options.isNotEmpty) {
        selections[g.id] = g.options[g.defaultIndex].id;
      }
    }
    // Editing an existing line — restore its choices + quantity + note + price.
    final edit = widget.editLine?.kind;
    if (edit is CartLineCafe) {
      selections
        ..clear()
        ..addAll(edit.selections);
      addOnQuantities.addAll(edit.addOnQuantities);
      quantity = widget.editLine!.quantity;
      notes = edit.note ?? '';
      _notesC.text = notes;
      if (edit.priceOverride != null) {
        _customPrice = (edit.priceOverride!.centavos ~/ 100).toString();
      }
    }
    // New custom-price line — seed the numpad with the suggested base price.
    if (widget.item.openPrice &&
        _customPrice.isEmpty &&
        widget.item.basePrice.centavos > 0) {
      _customPrice = (widget.item.basePrice.centavos ~/ 100).toString();
    }
  }

  @override
  void dispose() {
    _notesC.dispose();
    super.dispose();
  }

  /// Unit price using the tenant's global add-ons list. Walks two layers:
  /// the master option's priceDelta (set in Maintenance, applies to every
  /// product), then the per-product modifier_adjustments[].priceDelta (set
  /// on the product form, applies only to this product).
  Money get unitPrice {
    // Custom-price product — the typed amount is the price.
    if (widget.item.openPrice) return Money(_customPriceCents);
    final addOnsCatalog = context.read<AppState>().addOns;
    var total = widget.item.basePrice;
    for (final g in widget.item.modifierGroups) {
      final optId = selections[g.id];
      if (optId == null) continue;
      final opt = g.options.where((o) => o.id == optId).firstOrNull;
      if (opt != null) total = total + opt.priceDelta;
    }
    for (final adj in widget.item.modifierAdjustments) {
      if (selections[adj.groupId] != adj.optionId) continue;
      total = total + adj.priceDelta;
    }
    for (final entry in addOnQuantities.entries) {
      if (entry.value <= 0) continue;
      final addOn =
          addOnsCatalog.where((a) => a.id == entry.key).firstOrNull;
      if (addOn == null) continue;
      total = total + (addOn.priceDelta * entry.value);
    }
    return total;
  }

  Money get lineTotal => unitPrice * quantity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Container(
      width: size.width - 280,
      height: size.height * 0.82,
      margin: const EdgeInsets.symmetric(horizontal: 140),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(children: [
        Row(
          children: [
            // Hero (left) — emoji centered, stepper anchored at bottom
            Expanded(
              flex: 42,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [YColor.brandTint, YColor.surface1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon only for now (no product photo).
                          ProductVisual(
                            imageUrl: null,
                            name: widget.item.name,
                            iconName: widget.item.iconName,
                            size: 140,
                            iconSize: 80,
                            borderRadius: 28,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(
                              widget.item.name,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: YFont.titleLG().copyWith(
                                // Scale down for long titles (book names, etc.)
                                // so they fit without ellipsis on the third line.
                                fontSize: widget.item.name.length > 60
                                    ? 16
                                    : widget.item.name.length > 36
                                        ? 18
                                        : 22,
                                height: 1.2,
                              ),
                            ),
                          ),
                          // Sub-type the product belongs to (instead of a long
                          // description), as a small brand pill.
                          if (widget.item.categoryName.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: YColor.brandTint,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(widget.item.categoryName.trim(),
                                  style: YFont.caption().copyWith(
                                      color: YColor.brandDeep,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        children: [
                          Text('Quantity',
                              style: YFont.caption().copyWith(
                                color: YColor.brandDeep,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              )),
                          const SizedBox(height: 8),
                          _stepper(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Modifiers + CTA (right) — Add to Cart full width
            Expanded(
              flex: 58,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.item.openPrice) ...[
                            _openPriceSection(),
                            const SizedBox(height: 18),
                          ] else ...[
                            Row(children: [
                              Expanded(
                                child: Text('Customize : ${widget.item.name}',
                                    style: YFont.titleMD(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 12),
                              Text(unitPrice.formatted,
                                  style: YFont.priceLG()
                                      .copyWith(color: YColor.brand)),
                            ]),
                            const SizedBox(height: 22),
                            ...widget.item.modifierGroups.map(_modifierSection),
                            if (_visibleAddOns(context).isNotEmpty) ...[
                              _addOnsSection(),
                              const SizedBox(height: 16),
                            ],
                          ],
                          KeyboardAccessoryField(
                            controller: _notesC,
                            accessoryLabel: 'NOTES',
                            label: 'Notes',
                            hint: 'E.g., 2.5 kg, hardcover…',
                            maxLines: 2,
                            onChanged: (v) => notes = v,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(height: 0.5, color: YColor.hairline),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // Custom-price products: no price typed yet → blocked.
                        onPressed:
                            (widget.item.openPrice && _customPriceCents <= 0)
                                ? null
                                : _addToCart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.brand,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              YColor.inkMuted.withValues(alpha: 0.25),
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 18),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YRadius.md)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Icon(Icons.shopping_cart, size: 18),
                            Flexible(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  widget.editLine != null
                                      ? 'Update Cart'
                                      : 'Add to Cart',
                                  style: YFont.bodyStrong()
                                      .copyWith(color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Text(lineTotal.formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Cancel — top-left
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: YColor.surface1.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: YColor.hairline, width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.close, size: 14, color: YColor.ink),
                  const SizedBox(width: 6),
                  Text('Cancel',
                      style: YFont.bodyStrong().copyWith(fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _modifierSection(ModifierGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(group.name, style: YFont.bodyStrong()),
            if (group.required)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: YColor.brandTint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('REQUIRED',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: YColor.brand)),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options.map((o) {
              final selected = (selections[group.id] ?? group.options.first.id) == o.id;
              return GestureDetector(
                onTap: () => setState(() => selections[group.id] = o.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? YColor.brand : YColor.surface3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _labelFor(o),
                    style: YFont.bodyStrong().copyWith(
                      color: selected ? Colors.white : YColor.ink,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _labelFor(ModifierOption opt) =>
      opt.priceDelta.centavos > 0 ? '${opt.name} +${opt.priceDelta.compact}' : opt.name;

  Widget _addOnsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Add-ons', style: YFont.bodyStrong()),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: YColor.surface3,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OPTIONAL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: YColor.inkMuted,
                  )),
            ),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, c) {
            const gap = 10.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: 8,
              children: _visibleAddOns(context)
                  .map((a) => SizedBox(width: w, child: _addOnRow(a)))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  /// Add-ons that apply to this product's DB category.
  List<AddOn> _visibleAddOns(BuildContext ctx) {
    final all = ctx.watch<AppState>().addOns;
    return all
        .where((a) => a.appliesToCategory(widget.item.categoryId))
        .toList();
  }

  Widget _addOnRow(AddOn addOn) {
    final qty = addOnQuantities[addOn.id] ?? 0;
    final selected = qty > 0;
    final canIncrement = addOn.maxQuantity == 0 || qty < addOn.maxQuantity;

    void setQty(int n) {
      setState(() {
        if (n <= 0) {
          addOnQuantities.remove(addOn.id);
        } else {
          addOnQuantities[addOn.id] = n;
        }
      });
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? YColor.brandTint.withValues(alpha: 0.55)
            : YColor.surface3,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(
          color: selected ? YColor.brand : Colors.transparent,
          width: selected ? 1.4 : 0,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(addOn.name,
                  style: YFont.bodyStrong(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                addOn.priceDelta.centavos > 0
                    ? '+${addOn.priceDelta.formatted} each'
                    : 'Free',
                style: YFont.caption(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (!selected)
          ElevatedButton(
            onPressed: () => setQty(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('+',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, height: 1)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: YColor.surface1,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: YColor.hairline),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => setQty(qty - 1),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 16,
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: YFont.bodyStrong(),
                ),
              ),
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: canIncrement ? () => setQty(qty + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _stepper() {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YColor.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
          icon: const Icon(Icons.remove, size: 20),
          splashRadius: 20,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: YFont.titleMD().copyWith(fontSize: 18),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => quantity++),
          icon: const Icon(Icons.add, size: 20),
          splashRadius: 20,
        ),
      ]),
    );
  }

  /// Custom-price entry — big live amount + numpad (whole pesos).
  Widget _openPriceSection() {
    final has = _customPriceCents > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter price', style: YFont.titleMD()),
        const SizedBox(height: 4),
        Text(
          'Type the amount for this item, then add it to the cart.',
          style: YFont.caption().copyWith(color: YColor.inkMuted),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.lg),
              border:
                  Border.all(color: has ? YColor.brand : YColor.hairline),
            ),
            child: Text(
              '₱ ${has ? _customPrice : '0'}',
              style: YFont.titleLG().copyWith(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: has ? YColor.brand : YColor.inkSubtle,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OtpNumpad(
            keyWidth: 72,
            keyHeight: 50,
            onDigit: (d) => setState(() {
              if (_customPrice.length >= 7) return;
              // Drop a leading zero so "0" + "5" → "5".
              _customPrice =
                  (_customPrice + d).replaceFirst(RegExp(r'^0+(?=\d)'), '');
            }),
            onBackspace: () => setState(() {
              if (_customPrice.isNotEmpty) {
                _customPrice =
                    _customPrice.substring(0, _customPrice.length - 1);
              }
            }),
          ),
        ),
      ],
    );
  }

  void _addToCart() {
    final state = context.read<AppState>();
    final addOnSnapshots = <CartAddOn>[];
    for (final entry in addOnQuantities.entries) {
      if (entry.value <= 0) continue;
      final addOn =
          state.addOns.where((a) => a.id == entry.key).firstOrNull;
      if (addOn == null) continue;
      addOnSnapshots.add(CartAddOn(addOn, entry.value));
    }
    // Editing — drop the old line first so this replaces it.
    if (widget.editLine != null) state.cart.remove(widget.editLine!);
    final trimmedNote = notes.trim();
    state.cart.addCafe(
      widget.item,
      Map.from(selections),
      quantity: quantity,
      addOns: addOnSnapshots,
      priceOverride: widget.item.openPrice ? Money(_customPriceCents) : null,
      note: trimmedNote.isEmpty ? null : trimmedNote,
    );
    // Show the toast BEFORE popping — once the modal is gone, this context
    // is deactivated and Overlay.of() can't find the root overlay anymore.
    PushToast.show(
      context,
      title: widget.editLine != null ? 'Updated' : 'Added to cart',
      subtitle: '$quantity × ${widget.item.name}',
      leadingImageUrl: widget.item.imageUrl,
      leadingIconName: widget.item.iconName,
      leadingEmoji: widget.item.emoji,
    );
    Navigator.of(context).pop();
  }
}
