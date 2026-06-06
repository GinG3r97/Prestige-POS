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
              if (cart.lines.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Repeat order (read back)',
                  onPressed: () => _showRepeat(context, cart),
                  icon: const Icon(Icons.zoom_out_map, color: YColor.brandDeep),
                ),
                IconButton(
                  tooltip: 'Clear order',
                  onPressed: () => cart.clear(),
                  icon: const Icon(Icons.delete_outline, color: YColor.danger),
                ),
              ],
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
          // Must match the list's vertical padding (16 + 16) so the modal
          // height fully contains every row — including the last one.
          const pad = 32.0;

          // Bias toward going wide (up to 3 columns) so the modal stays short.
          final colByWidth = ((maxW - 80) / 230).floor().clamp(1, 3);
          var cols = n == 0 ? 1 : (n / 8).ceil();
          if (cols < 1) cols = 1;
          if (cols > colByWidth) cols = colByWidth;
          final rows = n == 0 ? 1 : (n / cols).ceil();

          final listMaxH =
              (maxH - 24 - headerH - totalH - pad).clamp(120.0, 100000.0);
          // Taller boxes so a long name can wrap to 2 lines (never truncated).
          final boxH =
              ((listMaxH - spacing * (rows - 1)) / rows).clamp(50.0, 74.0);
          final gridH = rows * boxH + spacing * (rows - 1);
          final fs = (boxH * 0.28).clamp(14.0, 18.0);

          // Wide boxes so most names fit on one line; the 2-line allowance
          // catches the longest. Uses most of the screen width.
          final cardW = (cols * 380.0 + 48).clamp(460.0, maxW - 36);
          final cardH = (headerH + totalH + gridH.clamp(0.0, listMaxH) + pad)
              .clamp(200.0, maxH - 12);

          Widget box(int idx) {
            final l = cart.lines[idx];
            return CustomPaint(
              foregroundPainter: _DashedBoxPainter(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  // Number + name + qty fill the left; the Expanded pushes the
                  // price to the far right.
                  Expanded(
                    child: Row(children: [
                      Text('${idx + 1}.',
                          style: YFont.bodyStrong().copyWith(
                              fontSize: fs * 0.9, color: YColor.inkMuted)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(l.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.bodyStrong().copyWith(
                                fontSize: fs,
                                color: YColor.ink,
                                height: 1.12)),
                      ),
                      const SizedBox(width: 8),
                      Text('x${l.quantity}',
                          style: YFont.bodyStrong().copyWith(
                              fontSize: fs,
                              color: YColor.brand,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  // Fixed right-aligned price column so they all line up.
                  SizedBox(
                    width: 96,
                    child: Text(l.lineTotal.formatted,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: YFont.bodyStrong().copyWith(
                            fontSize: fs, color: YColor.brandDeep)),
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
                        : Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int r = 0; r < rows; r++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                          bottom: r < rows - 1 ? spacing : 0),
                                      child: SizedBox(
                                        height: boxH,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            for (int c = 0; c < cols; c++) ...[
                                              if (c > 0)
                                                const SizedBox(width: spacing),
                                              Expanded(
                                                child: (c * rows + r) < n
                                                    ? box(c * rows + r)
                                                    : const SizedBox(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
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
