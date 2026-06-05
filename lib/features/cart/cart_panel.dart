import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../models/cart.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

class CartPanel extends StatelessWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // While the owner is arranging the menu, this panel becomes a mini tutorial
    // + a "Done editing" button instead of the order.
    if (context.watch<AppState>().arrangeMode) {
      return _arrangeHelp(context);
    }
    // Watch the cart only — cart edits repaint just this panel, not the
    // whole app (AppState no longer re-broadcasts cart changes).
    final cart = context.watch<CartStore>();
    return Container(
      color: YColor.surface1,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: YColor.hairline, width: 0.5)),
            ),
            child: Row(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Order', style: YFont.titleMD()),
                  Text('${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      style: YFont.caption()),
                ],
              ),
              const Spacer(),
              if (cart.lines.isNotEmpty)
                IconButton(
                  onPressed: () => cart.clear(),
                  icon: const Icon(Icons.delete_outline, color: YColor.danger),
                ),
            ]),
          ),
          // Body
          Expanded(
            child: cart.lines.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _line(cart.lines[i], cart),
                  ),
          ),
          // Totals + Pay
          if (cart.lines.isNotEmpty) _totals(context, cart),
        ],
      ),
    );
  }

  /// Replaces the order while the menu is being arranged: what you can do +
  /// the button to finish.
  Widget _arrangeHelp(BuildContext context) {
    return Container(
      color: YColor.surface1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: YColor.hairline, width: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.tune, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arranging menu', style: YFont.titleMD()),
                    Text('Order is paused while you edit',
                        style: YFont.caption()),
                  ],
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _tip(Icons.open_with, 'Hold & drag to reorder',
                    'Press and hold any box or product, then drag. Drag to an edge to auto-scroll to the start/end.'),
                _tip(Icons.touch_app_outlined, 'Tap to open',
                    'Tap a Type or Sub-type to view what\'s inside it.'),
                _tip(Icons.edit_outlined, 'Pencil to rename',
                    'Tap the ✎ on a Type/Sub-type to rename it. Tap a product to edit its name and price.'),
                _tip(Icons.add_box_outlined, 'Dashed + to add',
                    'Use the dashed + box to add a new Type, Sub-type, or Product.'),
                _tip(Icons.visibility_off_outlined, 'Faded = empty',
                    'Dimmed boxes have no products yet and sit at the end.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    context.read<AppState>().setArrangeMode(false),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Done editing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tip(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: YColor.brandDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: YFont.bodyStrong()),
              const SizedBox(height: 2),
              Text(body,
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _empty() {
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(color: YColor.brandTint, shape: BoxShape.circle),
              child: const Icon(Icons.shopping_cart_outlined, size: 34, color: YColor.brand),
            ),
            const SizedBox(height: 12),
            Text('Order is empty', style: YFont.titleMD()),
            const SizedBox(height: 4),
            Text(
              'Tap items from the catalog\nto start a new order',
              textAlign: TextAlign.center,
              style: YFont.body().copyWith(color: YColor.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(line, cart) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProductVisual(
          imageUrl: line.imageUrl,
          name: line.title,
          iconName: line.iconName,
          size: 44,
          iconSize: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.title, style: YFont.bodyStrong(), overflow: TextOverflow.ellipsis),
            if (line.subtitle != null) Text(line.subtitle, style: YFont.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              _qtyBtn(Icons.remove, () => cart.setQuantity(line, line.quantity - 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${line.quantity}', style: YFont.bodyStrong()),
              ),
              _qtyBtn(Icons.add, () => cart.setQuantity(line, line.quantity + 1)),
              const Spacer(),
              Text(line.lineTotal.formatted, style: YFont.bodyStrong()),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: YColor.surface3, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 14),
        ),
      );

  Widget _totals(BuildContext context, CartStore cart) {
    return Container(
      // The cart panel sits flush against the right edge of the Sell
      // layout; the floating bottom nav lives in the centre and doesn't
      // overlap this column, so we don't need the old 120px bottom inset
      // — the Pay button hugs the bottom of the screen.
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: YColor.hairline, width: 0.5)),
      ),
      child: Column(
        children: [
          _totalRow('Subtotal', cart.subtotal.formatted),
          _totalRow('VAT (incl.)', cart.vat.formatted, faded: true),
          const SizedBox(height: 8),
          const Divider(color: YColor.hairline, height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Text('Total', style: YFont.titleMD()),
            const Spacer(),
            Text(cart.total.formatted, style: YFont.titleMD().copyWith(color: YColor.brand)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.read<AppState>().openTender(),
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YRadius.md)),
              ),
              child: Text('Pay ${cart.total.formatted}', style: YFont.bodyStrong().copyWith(color: Colors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {Color? tint, bool faded = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(label, style: YFont.body().copyWith(color: faded ? YColor.inkMuted : YColor.ink)),
        const Spacer(),
        Text(value,
            style: YFont.bodyStrong().copyWith(
                color: tint ?? (faded ? YColor.inkMuted : YColor.ink))),
      ]),
    );
  }
}
