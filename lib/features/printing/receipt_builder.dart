import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../../models/order.dart' as o;
import '../../models/printer_config.dart';
import '../../models/tenant.dart';

/// Generates ESC/POS byte streams for receipts + kitchen slips.
///
/// Pure Dart — runs the same on iOS / Android / macOS / Windows / Linux.
/// Use [bir] for the customer receipt and [kitchen] for the kitchen ticket.
/// Both return raw bytes ready to be written to a TCP socket (LAN
/// thermal printers listen on port 9100) or a Bluetooth characteristic.
class ReceiptBuilder {
  ReceiptBuilder._();

  /// BIR-style customer receipt. Header carries the business name +
  /// address, then order metadata, then line items with modifiers /
  /// add-ons + per-line totals, then a totals block (subtotal, VAT incl,
  /// total) + payment + cashier footer.
  static Future<List<int>> bir({
    required o.Order order,
    required Tenant tenant,
    required PrinterConfig printer,
    String? footerMessage,
    Uint8List? logoBytes,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];

    bytes.addAll(g.reset());

    // ─── Logo (optional) ───
    if (logoBytes != null) {
      final decoded = img.decodeImage(logoBytes);
      if (decoded != null) {
        // Printable dot width: 80mm heads are 576 dots, 58mm are 384. Keep
        // the logo to roughly two-thirds of that so it sits centered with
        // margin and prints crisp.
        final targetW = printer.paperWidth == 80 ? 360 : 288;
        final scaled = decoded.width > targetW
            ? img.copyResize(decoded,
                width: targetW, interpolation: img.Interpolation.average)
            : decoded;
        bytes.addAll(g.image(img.grayscale(scaled), align: PosAlign.center));
        bytes.addAll(g.feed(1));
      }
    }

    // ─── Header ───
    bytes.addAll(g.text(tenant.businessName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )));
    if (tenant.address.trim().isNotEmpty) {
      bytes.addAll(g.text(tenant.address.trim(),
          styles: const PosStyles(align: PosAlign.center)));
    }
    // Custom header lines (e.g. TIN, tagline) — one printed line each, using
    // the owner's chosen alignment.
    final headerAlign =
        tenant.receiptAlign == 'left' ? PosAlign.left : PosAlign.center;
    final header = tenant.receiptHeader?.trim() ?? '';
    if (header.isNotEmpty) {
      for (final line in header.split('\n')) {
        bytes.addAll(g.text(line, styles: PosStyles(align: headerAlign)));
      }
    }
    bytes.addAll(g.feed(1));
    bytes.addAll(g.hr());

    // ─── Order meta ───
    final ts = _fmtDateTime(order.paidAt ?? order.createdAt);
    bytes.addAll(g.row([
      PosColumn(
          text: 'Order #${order.orderNumber.toString().padLeft(4, '0')}',
          width: 6,
          styles: const PosStyles(bold: true)),
      PosColumn(
          text: ts,
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]));
    if ((order.cashierName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text('Cashier: ${order.cashierName}',
          styles: const PosStyles(align: PosAlign.left)));
    }
    if ((order.customerName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text('Customer: ${order.customerName}',
          styles: const PosStyles(align: PosAlign.left)));
    }
    bytes.addAll(g.hr());

    // ─── Line items ───
    for (final line in order.lines) {
      // Name + qty x unit  ────────  line total
      bytes.addAll(g.row([
        PosColumn(
          text: '${line.quantity}× ${line.name}',
          width: 8,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: _peso(line.lineTotalCents),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]));
      // Unit price subline (only when qty > 1, otherwise redundant).
      if (line.quantity > 1) {
        bytes.addAll(g.text('  @ ${_peso(line.unitPriceCents)}',
            styles: const PosStyles(align: PosAlign.left)));
      }
      // Modifier / add-on details from the snapshot jsonb.
      final mods = line.modifiers;
      if (mods != null) {
        final opts = mods['options'];
        if (opts is Map) {
          for (final entry in opts.entries) {
            bytes.addAll(g.text('  · ${entry.key}: ${entry.value}'));
          }
        }
        final addOns = mods['add_ons'];
        if (addOns is List) {
          for (final a in addOns) {
            if (a is Map) {
              final name = a['name'];
              final qty = a['quantity'];
              bytes.addAll(g.text('  + $qty× $name'));
            }
          }
        }
      }
    }
    bytes.addAll(g.hr());

    // ─── Totals ───
    bytes.addAll(_kv(g, 'Subtotal', _peso(order.subtotalCents)));
    if (order.discountCents > 0) {
      bytes.addAll(_kv(g, 'Discount', '-${_peso(order.discountCents)}'));
    }
    bytes.addAll(_kv(g, 'VAT (incl.)', _peso(order.vatCents),
        fadedFirstCol: true));
    bytes.addAll(g.hr(ch: '='));
    bytes.addAll(g.row([
      PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(
          text: _peso(order.totalCents),
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          )),
    ]));
    bytes.addAll(g.hr());

    // ─── Payment(s) ───
    for (final p in order.payments) {
      bytes.addAll(_kv(g, _paymentLabel(p.method), _peso(p.amountCents)));
      if (p.tenderedCents != null && p.method == o.OrderPaymentMethod.cash) {
        bytes.addAll(_kv(g, '  Tendered', _peso(p.tenderedCents!)));
        if (p.changeCents != null) {
          bytes.addAll(_kv(g, '  Change', _peso(p.changeCents!)));
        }
      }
      if ((p.reference ?? '').isNotEmpty) {
        bytes.addAll(g.text('  Ref: ${p.reference}'));
      }
    }
    bytes.addAll(g.feed(1));

    // ─── Footer ───
    // Custom footer (multi-line) overrides the default thank-you line, using
    // the owner's chosen alignment.
    final footer = (footerMessage ?? tenant.receiptFooter)?.trim();
    if (footer != null && footer.isNotEmpty) {
      for (final line in footer.split('\n')) {
        bytes.addAll(
            g.text(line, styles: PosStyles(align: headerAlign, bold: true)));
      }
    } else {
      bytes.addAll(g.text('Thank you — please come again!',
          styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }

  /// Kitchen slip — for the cooks. NO prices, big item names + sizes /
  /// modifiers / notes. The order number is huge so anyone glancing at
  /// the printer queue knows which ticket is which.
  static Future<List<int>> kitchen({
    required o.Order order,
    required PrinterConfig printer,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];

    bytes.addAll(g.reset());

    bytes.addAll(g.text('ORDER',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        )));
    bytes.addAll(g.text('#${order.orderNumber.toString().padLeft(4, '0')}',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size3,
          width: PosTextSize.size3,
        )));
    bytes.addAll(g.text(_fmtDateTime(order.paidAt ?? order.createdAt),
        styles: const PosStyles(align: PosAlign.center)));
    if ((order.customerName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text('For: ${order.customerName}',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
          )));
    }
    bytes.addAll(g.hr(ch: '='));

    for (final line in order.lines) {
      bytes.addAll(g.text(
        '${line.quantity}× ${line.name}',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ));
      final mods = line.modifiers;
      if (mods != null) {
        final opts = mods['options'];
        if (opts is Map) {
          for (final entry in opts.entries) {
            bytes.addAll(g.text('  · ${entry.key}: ${entry.value}',
                styles: const PosStyles(bold: true)));
          }
        }
        final addOns = mods['add_ons'];
        if (addOns is List) {
          for (final a in addOns) {
            if (a is Map) {
              bytes.addAll(g.text('  + ${a['quantity']}× ${a['name']}',
                  styles: const PosStyles(bold: true)));
            }
          }
        }
      }
      bytes.addAll(g.feed(1));
    }

    if ((order.notes ?? '').trim().isNotEmpty) {
      bytes.addAll(g.hr());
      bytes.addAll(g.text('Notes:',
          styles: const PosStyles(bold: true)));
      bytes.addAll(g.text(order.notes!.trim()));
    }

    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }

  // ─── helpers ──────────────────────────────────────────────────────

  static List<int> _kv(Generator g, String k, String v,
      {bool fadedFirstCol = false}) {
    return g.row([
      PosColumn(
        text: k,
        width: 8,
        styles: PosStyles(bold: !fadedFirstCol),
      ),
      PosColumn(
        text: v,
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  static String _peso(int cents) {
    final pesos = cents / 100;
    return '₱${pesos.toStringAsFixed(2)}';
  }

  static String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _paymentLabel(o.OrderPaymentMethod m) => switch (m) {
        o.OrderPaymentMethod.cash => 'Cash',
        o.OrderPaymentMethod.gcash => 'GCash',
        o.OrderPaymentMethod.paymaya => 'Maya',
        o.OrderPaymentMethod.card => 'Card',
        _ => 'Other',
      };
}

/// Tiny wrapper so existing callers can keep using `Uint8List` without
/// casting. ESC/POS generators return `List<int>`; sockets want bytes.
extension EscPosBytesX on List<int> {
  Uint8List asBytes() => Uint8List.fromList(this);
}
