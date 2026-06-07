import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../models/cart.dart';
import '../../models/held_order.dart';
import '../../models/money.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../cafe/product_detail_sheet.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

class CartPanel extends StatefulWidget {
  const CartPanel({super.key});

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  bool _showHeld = false;
  bool _showBreakdown = false; // Subtotal + VAT rows (collapsed by default)
  final ScrollController _cartScroll = ScrollController();
  int _prevLineCount = 0;

  @override
  void dispose() {
    _cartScroll.dispose();
    super.dispose();
  }

  /// Small labelled box button used in the cart header (Repeat, Hold / Clear).
  Widget _headerChip(String label, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? YColor.danger : YColor.brandDeep;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YRadius.sm),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: YFont.caption()
                .copyWith(color: c, fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // While the owner is arranging the menu, this panel becomes a mini tutorial
    // + a "Done editing" button instead of the order.
    if (app.arrangeMode) return _arrangeHelp(context);

    final cart = context.watch<CartStore>();
    // When a new line is rung up, scroll the order to it so the cashier never
    // has to reach for it.
    if (cart.lines.length > _prevLineCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_cartScroll.hasClients) {
          _cartScroll.animateTo(
            _cartScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _prevLineCount = cart.lines.length;
    final heldCount = app.heldOrders.length;
    if (heldCount == 0 && _showHeld) _showHeld = false;

    return ClipRect(
      // Keep the swipe-to-remove gesture (and anything else) inside the cart
      // column so it never bleeds over the product grid on the left.
      child: Container(
      color: YColor.surface1,
      child: Column(
        children: [
          // Current | Held toggle — only once there's something parked.
          if (heldCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Row(children: [
                Expanded(
                    child: _segBtn('Current', !_showHeld,
                        () => setState(() => _showHeld = false))),
                const SizedBox(width: 8),
                Expanded(
                    child: _segBtn('Held ($heldCount)', _showHeld,
                        () => setState(() => _showHeld = true))),
              ]),
            ),
          Expanded(
            child: _showHeld
                ? _heldList(context, app)
                : _currentView(context, cart),
          ),
        ],
      ),
      ),
    );
  }

  Widget _segBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? YColor.brand : YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.sm),
          border: Border.all(color: active ? YColor.brand : YColor.hairline),
        ),
        child: Text(label,
            style: YFont.bodyStrong().copyWith(
                fontSize: 12.5, color: active ? Colors.white : YColor.ink)),
      ),
    );
  }

  Widget _currentView(BuildContext context, CartStore cart) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: YColor.hairline, width: 0.5)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Order',
                      style: YFont.titleMD(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                      '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      style: YFont.caption()),
                ],
              ),
            ),
            if (cart.lines.isNotEmpty) ...[
              _headerChip('Repeat', () => _showRepeat(context, cart)),
              const SizedBox(width: 6),
              _headerChip('Hold / Clear',
                  () => _showOrderActions(context, cart),
                  danger: true),
            ],
          ]),
        ),
        Expanded(
          child: cart.lines.isEmpty
              ? _empty()
              : ListView.separated(
                  controller: _cartScroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _line(cart.lines[i], cart),
                ),
        ),
        if (cart.lines.isNotEmpty) _totals(context, cart),
      ],
    );
  }

  // ── Held orders ────────────────────────────────────────────────────────

  Widget _heldList(BuildContext context, AppState app) {
    final held = app.heldOrders;
    if (held.isEmpty) {
      return Center(
        child: Text('No held orders',
            style: YFont.body().copyWith(color: YColor.inkMuted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: held.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final h = held[i];
        return Dismissible(
          key: ValueKey(h.id),
          direction: DismissDirection.endToStart, // swipe left to discard
          onDismissed: (_) => app.discardHeldOrder(h),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(
              color: YColor.danger,
              borderRadius: BorderRadius.circular(YRadius.md),
            ),
            child:
                const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.md),
              border: Border.all(color: YColor.hairline),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.label,
                        style: YFont.bodyStrong(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                        '${h.itemCount} item${h.itemCount == 1 ? '' : 's'} · '
                        '${Money(h.totalCents).formatted}',
                        style: YFont.caption()),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _resume(context, app, h),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Resume'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _resume(BuildContext context, AppState app, HeldOrder h) {
    if (app.cart.lines.isNotEmpty) {
      PushToast.show(context,
          title: 'Finish the current order first',
          subtitle: 'Charge or hold the current order, then resume this one.',
          leadingIcon: Icons.info_outline);
      return;
    }
    app.resumeHeldOrder(h);
    setState(() => _showHeld = false);
  }

  /// Tapping the order menu → choose what to do with this order: hold it for a
  /// customer, or clear it. Two big tappable cards.
  void _showOrderActions(BuildContext context, CartStore cart) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: YColor.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Text('Order', style: YFont.titleMD()),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: _actionBox(
                      icon: Icons.bookmark_add_outlined,
                      label: 'Hold for later',
                      color: YColor.brand,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showHoldName(context, cart);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionBox(
                      icon: Icons.delete_outline,
                      label: 'Clear cart',
                      color: YColor.danger,
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final ok = await showConfirm(context,
                            title: 'Clear this order?',
                            message:
                                'This empties the cart and can’t be undone.',
                            confirmLabel: 'Clear cart',
                            danger: true,
                            icon: Icons.delete_outline);
                        if (ok) cart.clear();
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBox({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(label,
              textAlign: TextAlign.center,
              style: YFont.bodyStrong().copyWith(color: color)),
        ]),
      ),
    );
  }

  /// Step 2 after "Hold for later" — name it for the customer (optional).
  void _showHoldName(BuildContext context, CartStore cart) {
    final app = context.read<AppState>();
    final nameC = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: YColor.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Hold order', style: YFont.titleMD()),
                const SizedBox(height: 4),
                Text('Name the order so you can find it later.',
                    style: YFont.caption().copyWith(color: YColor.inkMuted)),
                const SizedBox(height: 14),
                KeyboardAccessoryField(
                  controller: nameC,
                  accessoryLabel: 'CUSTOMER NAME / TABLE #',
                  hint: 'e.g. Maria · Table 4',
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: YColor.ink,
                        side: const BorderSide(color: YColor.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(YRadius.md)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Required — Hold stays disabled until a name/table is typed.
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: nameC,
                      builder: (_, val, __) {
                        final ok = val.text.trim().isNotEmpty;
                        return ElevatedButton(
                          onPressed: ok
                              ? () {
                                  app.holdCurrentOrder(
                                      label: nameC.text.trim());
                                  Navigator.of(ctx).pop();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: YColor.brand,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: YColor.surface3,
                            disabledForegroundColor: YColor.inkMuted,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(YRadius.md)),
                          ),
                          child: const Text('Hold'),
                        );
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
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

  Widget _line(CartLine line, CartStore cart) {
    return Dismissible(
      key: ValueKey(line.id),
      direction: DismissDirection.endToStart, // swipe left to remove
      onDismissed: (_) => cart.remove(line),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: YColor.danger,
          borderRadius: BorderRadius.circular(YRadius.md),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
      ),
      child: CustomPaint(
        foregroundPainter: _DashedBoxPainter(),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(line.title,
                      style: YFont.bodyStrong().copyWith(height: 1.1),
                      overflow: TextOverflow.ellipsis),
                ),
                // Edit — only for customizable cafe items.
                if (line.kind is CartLineCafe) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _editLine(context, line),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: YColor.brandDeep.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(YRadius.sm),
                        border: Border.all(
                            color: YColor.brandDeep.withValues(alpha: 0.3)),
                      ),
                      child: Text('Edit',
                          style: YFont.caption().copyWith(
                              color: YColor.brandDeep,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ),
                  ),
                ],
              ]),
              if (line.subtitle != null &&
                  line.subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(line.subtitle!,
                    style: YFont.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              Row(children: [
                _qtyBtn(Icons.remove,
                    () => cart.setQuantity(line, line.quantity - 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${line.quantity}', style: YFont.bodyStrong()),
                ),
                _qtyBtn(Icons.add,
                    () => cart.setQuantity(line, line.quantity + 1)),
                const Spacer(),
                Text(line.lineTotal.formatted, style: YFont.bodyStrong()),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Re-open the product sheet to edit this line's choices (replaces it).
  void _editLine(BuildContext context, CartLine line) {
    final k = line.kind;
    if (k is! CartLineCafe) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => ProductDetailSheet(item: k.item, editLine: line),
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
          // Subtotal + VAT — collapsed by default, animates open/closed.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _showBreakdown
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _totalRow('Subtotal', cart.subtotal.formatted),
                        _totalRow('VAT (incl.)', cart.vat.formatted,
                            faded: true),
                        const SizedBox(height: 8),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
          // Separator with a labelled SHOW/HIDE VAT toggle in the centre.
          SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Divider(color: YColor.hairline, height: 1),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showBreakdown = !_showBreakdown),
                  child: Container(
                    color: YColor.surface1,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                      decoration: BoxDecoration(
                        color: YColor.surface2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: YColor.hairline),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            _showBreakdown
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            size: 16,
                            color: YColor.brandDeep),
                        const SizedBox(width: 2),
                        Text(_showBreakdown ? 'HIDE VAT' : 'SHOW VAT',
                            style: YFont.caption().copyWith(
                                color: YColor.brandDeep,
                                fontWeight: FontWeight.w700,
                                fontSize: 11)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  void _showRepeat(BuildContext context, CartStore cart) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      barrierLabel: 'Repeat order',
      pageBuilder: (_, __, ___) => const _RepeatOrderView(),
    );
  }
}

/// A read-only blow-up of the current order for reading it back to the
/// customer. Each item is a uniform single-line dashed (brown) box —
/// "1.  ×2  Fries  ₱125" — and the boxes flow into a grid (up to 3 columns)
/// that fits on one screen, filled column-by-column.
class _RepeatOrderView extends StatelessWidget {
  const _RepeatOrderView();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final n = cart.lines.length;
    const spacing = 8.0;

    return SafeArea(
      child: Center(
        child: LayoutBuilder(builder: (context, screen) {
          final maxW = screen.maxWidth;
          final maxH = screen.maxHeight;

          const headerH = 56.0;
          const totalH = 58.0;
          const fs = 17.0;
          const colW = 340.0;
          // 4 items per column; add more columns to the right.
          final cardH = (maxH - 24).clamp(240.0, maxH - 12);

          // sub-type · modifiers + add-ons text for a line (shared by the box
          // widget and the height estimate below).
          (String, String?) infoFor(int idx) {
            final k = cart.lines[idx].kind;
            final cafe = k is CartLineCafe ? k : null;
            final mods = <String>[];
            final addons = <String>[];
            if (cafe != null) {
              for (final g in cafe.item.modifierGroups) {
                final optId = cafe.selections[g.id];
                if (optId == null) continue;
                for (final o in g.options) {
                  if (o.id == optId) {
                    mods.add(o.name);
                    break;
                  }
                }
              }
              for (final a in cafe.addOns) {
                addons.add('${a.quantity}× ${a.addOn.name}');
              }
            }
            final detail = [
              if ((cafe?.item.categoryName ?? '').trim().isNotEmpty)
                cafe!.item.categoryName.trim(),
              ...mods,
            ].join(' · ');
            return (
              detail,
              addons.isEmpty ? null : 'Add-ons: ${addons.join(', ')}'
            );
          }

          // Estimated rendered height of a box — its text wraps at ~180px
          // beside the price column. Drives the auto-fit packing.
          double textH(String t, double size, {int? maxLines}) {
            final tp = TextPainter(
              text: TextSpan(
                  text: t, style: TextStyle(fontSize: size, height: 1.2)),
              maxLines: maxLines,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: 180);
            return tp.height;
          }

          double estBoxH(int idx) {
            final (detail, addOnsLine) = infoFor(idx);
            var h = 12.0;
            h += textH(cart.lines[idx].title, fs, maxLines: 2);
            if (detail.isNotEmpty) h += textH(detail, fs * 0.74, maxLines: 2);
            if (addOnsLine != null) h += textH(addOnsLine, fs * 0.74) + 2;
            return h + 4;
          }

          // Pack boxes top-to-bottom; start a new column when the next box
          // wouldn't fit the modal's height.
          final availH = (cardH - headerH - totalH - 32).clamp(120.0, 100000.0);
          final columns = <List<int>>[];
          var cur = <int>[];
          var runH = 0.0;
          for (var i = 0; i < n; i++) {
            final bh = estBoxH(i);
            final next = cur.isEmpty ? bh : runH + spacing + bh;
            if (cur.isNotEmpty && next > availH) {
              columns.add(cur);
              cur = [i];
              runH = bh;
            } else {
              cur.add(i);
              runH = next;
            }
          }
          if (cur.isNotEmpty) columns.add(cur);
          if (columns.isEmpty) columns.add(<int>[]);

          final perShelf = ((maxW - 60) / (colW + spacing))
              .floor()
              .clamp(1, columns.length);
          final cardW = (perShelf * colW + (perShelf - 1) * spacing + 40)
              .clamp(360.0, maxW - 36);

          Widget box(int idx) {
            final l = cart.lines[idx];
            final (detail, addOnsLine) = infoFor(idx);
            return CustomPaint(
              foregroundPainter: _DashedBoxPainter(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Number + name + add-ons fill the left; price on the right.
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text('${idx + 1}.',
                          style: YFont.bodyStrong().copyWith(
                              fontSize: fs * 0.9, color: YColor.inkMuted)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong().copyWith(
                                    fontSize: fs,
                                    color: YColor.ink,
                                    height: 1.12)),
                            if (detail.isNotEmpty)
                              Text(detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: YFont.caption().copyWith(
                                      fontSize: fs * 0.74,
                                      color: YColor.inkMuted)),
                            // Add-ons wrap onto new lines (no ellipsis) — the
                            // box grows to fit them.
                            if (addOnsLine != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(addOnsLine,
                                    style: YFont.caption().copyWith(
                                        fontSize: fs * 0.74,
                                        color: YColor.brandDeep)),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  // Right column: price, then the multiplier beneath it (small
                  // + muted, same size as the sub-type), both right-aligned.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(l.lineTotal.formatted,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: YFont.bodyStrong().copyWith(
                                fontSize: fs, color: YColor.brandDeep)),
                      ),
                      Text('x${l.quantity}',
                          textAlign: TextAlign.right,
                          style: YFont.caption().copyWith(
                              fontSize: fs * 0.74, color: YColor.inkMuted)),
                    ],
                  ),
                ]),
              ),
            );
          }

          return Material(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: Column(
                children: [
                  SizedBox(
                    height: headerH,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: YColor.hairline)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.receipt_long,
                            color: YColor.brandDeep, size: 22),
                        const SizedBox(width: 10),
                        Text('Order summary',
                            style: YFont.titleMD().copyWith(fontSize: 19)),
                        const Spacer(),
                        Text(
                            '${cart.itemCount} item'
                            '${cart.itemCount == 1 ? '' : 's'}',
                            style: YFont.caption()),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 24),
                        ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: n == 0
                        ? Center(
                            child: Text('Order is empty',
                                style: YFont.titleMD()
                                    .copyWith(color: YColor.inkMuted)))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                // Columns of up to 4 items; boxes size to their
                                // content (add-ons wrap onto new lines).
                                for (final col in columns)
                                  SizedBox(
                                    width: colW,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var i = 0; i < col.length; i++)
                                          Padding(
                                            padding: EdgeInsets.only(
                                                bottom: i < col.length - 1
                                                    ? spacing
                                                    : 0),
                                            child: box(col[i]),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  SizedBox(
                    height: totalH,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: const BoxDecoration(
                        color: YColor.surface2,
                        border:
                            Border(top: BorderSide(color: YColor.hairline)),
                      ),
                      child: Row(children: [
                        Text('Total',
                            style: YFont.titleMD().copyWith(fontSize: 20)),
                        const Spacer(),
                        Text(cart.total.formatted,
                            style: YFont.titleMD().copyWith(
                                fontSize: 24,
                                color: YColor.brand,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Dashed brown rounded-rect border for the read-back item boxes.
class _DashedBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Inset by 1px so the stroke stays fully inside the box and isn't clipped
    // at the modal's top/bottom edges.
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1), const Radius.circular(10));
    final src = Path()..addRRect(rrect);
    final dashed = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        dashed.addPath(m.extractPath(d, d + 5), Offset.zero);
        d += 9;
      }
    }
    canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = YColor.brandDeep);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
