import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../../models/order.dart' as o;
import '../../models/printer_config.dart';
import '../../models/shift.dart';
import '../../models/tenant.dart';

/// Generates ESC/POS byte streams for receipts + kitchen slips.
///
/// Pure Dart — runs the same on iOS / Android / macOS / Windows / Linux.
/// Use [bir] for the customer receipt and [kitchen] for the kitchen ticket.
/// Both return raw bytes ready to be written to a TCP socket (LAN
/// thermal printers listen on port 9100) or a Bluetooth characteristic.
class ReceiptBuilder {
  ReceiptBuilder._();

  /// ESC/POS cash-drawer "kick" — pulses the drawer wired to the printer's
  /// RJ11/RJ12 port so it pops open. Command is `ESC p m t1 t2`:
  ///   • `m`  selects the connector pin: 0 = pin 2 (the common default),
  ///          1 = pin 5 (some drawers). Set [pin5] true only if pin 2 does
  ///          nothing on your hardware.
  ///   • `t1/t2` are the pulse on/off times in 2 ms units; 25/250 (0x19/0xFA)
  ///          is the widely-compatible default.
  /// Sending this to a printer with no drawer attached is harmless — the
  /// printer simply ignores the pulse.
  static List<int> drawerKick({bool pin5 = false}) =>
      [0x1B, 0x70, pin5 ? 0x01 : 0x00, 0x19, 0xFA];

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
    bool reprint = false,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];

    bytes.addAll(g.reset());

    // Layout template: 1 = Standard, 2 = Compact (no logo/address/header,
    // tighter), 3 = Official (adds an OFFICIAL RECEIPT label + closing line).
    final tmpl = tenant.receiptTemplate;
    final compact = tmpl == 2;
    final official = tmpl == 3;
    final font =
        tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA;

    // A store counts as "BIR-configured" once it has entered a TIN. Then we
    // print the compliant Sales Invoice format (registration header, VAT
    // breakdown, BIR footer) instead of the plain receipt.
    final birReady = (tenant.tin ?? '').trim().isNotEmpty;

    // ─── Logo (optional, hidden on Compact) ───
    if (logoBytes != null && !compact) {
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
    bytes.addAll(g.text(_san(tenant.businessName),
        styles: PosStyles(fontType: font, 
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )));
    if (tenant.address.trim().isNotEmpty && !compact) {
      bytes.addAll(g.text(_san(tenant.address.trim()),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
    }
    // ─── BIR registration header ───
    if (birReady) {
      final vatLabel = tenant.vatRegistered ? 'VAT REG TIN' : 'NON-VAT TIN';
      bytes.addAll(g.text(_san('$vatLabel: ${tenant.tin}'),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
      final idBits = <String>[];
      if ((tenant.birMin ?? '').trim().isNotEmpty) {
        idBits.add('MIN ${tenant.birMin}');
      }
      if ((tenant.birSerial ?? '').trim().isNotEmpty) {
        idBits.add('SN ${tenant.birSerial}');
      }
      if (idBits.isNotEmpty) {
        bytes.addAll(g.text(_san(idBits.join('  ')),
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
      bytes.addAll(g.text(_san('Branch: ${tenant.branchCode}'),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
    }
    // Custom header lines (e.g. TIN, tagline) — always printed (it's managed
    // separately in Settings → Receipt header & footer); templates only
    // control the built-in logo/address/layout, not your custom text.
    final headerAlign =
        tenant.receiptAlign == 'left' ? PosAlign.left : PosAlign.center;
    final header = tenant.receiptHeader?.trim() ?? '';
    if (header.isNotEmpty) {
      for (final line in header.split('\n')) {
        bytes.addAll(g.text(_san(line), styles: PosStyles(fontType: font, align: headerAlign)));
      }
    }
    // Document title — "Sales Invoice" per the EOPT Act (Official Receipt was
    // renamed to Invoice). Printed when BIR-configured or on the Official tmpl.
    if (birReady || official) {
      bytes.addAll(g.text('SALES INVOICE',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    }
    // Status / reprint banners.
    if (order.status == o.OrderStatus.voided) {
      bytes.addAll(g.text('*** VOID ***',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    } else if (order.status == o.OrderStatus.refunded) {
      bytes.addAll(g.text('*** REFUNDED ***',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    }
    if (reprint) {
      bytes.addAll(g.text('*** REPRINT ***',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    }
    if (!compact) bytes.addAll(g.feed(1));
    bytes.addAll(g.hr());

    // ─── Order meta ───
    // Order # and date on their own full-width lines — the long date would
    // wrap (and drop the "M" of AM/PM) if squeezed into a half-width column.
    final ts = _fmtDateTime(order.paidAt ?? order.createdAt);
    final invoiceLine = birReady
        ? 'Invoice No: ${order.orderNumber.toString().padLeft(7, '0')}'
        : 'Order #${order.orderNumber.toString().padLeft(4, '0')}';
    bytes.addAll(g.text(invoiceLine,
        styles: PosStyles(fontType: font, bold: true)));
    bytes.addAll(g.text(ts, styles: PosStyles(fontType: font)));
    if ((order.cashierName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text(_san('Cashier: ${order.cashierName}'),
          styles: PosStyles(fontType: font, align: PosAlign.left)));
    }
    if ((order.customerName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text(_san('Customer: ${order.customerName}'),
          styles: PosStyles(fontType: font, align: PosAlign.left)));
    }
    bytes.addAll(g.hr());

    // ─── Line items ───
    for (final line in order.lines) {
      // Name + qty x unit  ────────  line total
      bytes.addAll(g.row([
        PosColumn(
          text: _san('${line.quantity}× ${line.name}'),
          width: 8,
          styles: PosStyles(fontType: font, bold: true),
        ),
        PosColumn(
          text: _peso(line.lineTotalCents),
          width: 4,
          styles: PosStyles(fontType: font, align: PosAlign.right, bold: true),
        ),
      ]));
      // Unit price subline (only when qty > 1; skipped on Compact).
      if (line.quantity > 1 && !compact) {
        bytes.addAll(g.text('  @ ${_peso(line.unitPriceCents)}',
            styles: PosStyles(fontType: font, align: PosAlign.left)));
      }
      // Modifier / add-on details from the snapshot jsonb.
      final mods = line.modifiers;
      if (mods != null) {
        final opts = mods['options'];
        if (opts is Map) {
          for (final entry in opts.entries) {
            bytes.addAll(g.text(_san('  · ${entry.key}: ${entry.value}')));
          }
        }
        final addOns = mods['add_ons'];
        if (addOns is List) {
          for (final a in addOns) {
            if (a is Map) {
              final name = a['name'];
              final qty = a['quantity'];
              bytes.addAll(g.text(_san('  + $qty× $name')));
            }
          }
        }
      }
    }
    bytes.addAll(g.hr());

    // ─── Totals ───
    if (order.isScPwd) {
      // Senior / PWD: strip VAT (if VAT-registered) then 20% off the net.
      final sub = order.subtotalCents;
      final net = tenant.vatRegistered ? (sub / 1.12).round() : sub;
      final vat = sub - net;
      final scDisc = net - order.totalCents; // the 20% portion
      bytes.addAll(_kv(g, 'Total Sales', _peso(sub), font: font));
      if (tenant.vatRegistered) {
        bytes.addAll(_kv(g, 'Less: VAT', '-${_peso(vat)}', font: font));
        bytes.addAll(_kv(g, 'Net of VAT', _peso(net), font: font));
      }
      bytes.addAll(_kv(
          g,
          order.scPwdType == 'senior'
              ? 'Less: 20% SC Disc'
              : 'Less: 20% PWD Disc',
          '-${_peso(scDisc)}',
          font: font));
    } else {
      bytes.addAll(_kv(g, 'Subtotal', _peso(order.subtotalCents), font: font));
      if (order.discountCents > 0) {
        bytes.addAll(
            _kv(g, 'Discount', '-${_peso(order.discountCents)}', font: font));
      }
      if (birReady && tenant.vatRegistered) {
        // Sales are VAT-inclusive; back out the 12% for the BIR breakdown.
        // Phase 1 treats all items as VATable (exempt/zero-rated = 0).
        final net = (order.totalCents / 1.12).round();
        final vat = order.totalCents - net;
        bytes.addAll(_kv(g, 'VATable Sales', _peso(net), font: font));
        bytes.addAll(_kv(g, 'VAT-Exempt Sales', _peso(0), font: font));
        bytes.addAll(_kv(g, 'Zero-Rated Sales', _peso(0), font: font));
        bytes.addAll(_kv(g, 'VAT (12%)', _peso(vat), font: font));
      } else if (!birReady) {
        // vat_cents isn't computed server-side, so back it out of the
        // VAT-inclusive total instead of printing a stored 0.
        final vat = order.totalCents - (order.totalCents / 1.12).round();
        bytes.addAll(_kv(g, 'VAT (incl.)', _peso(vat),
            fadedFirstCol: true, font: font));
      }
    }
    bytes.addAll(g.hr(ch: '='));
    bytes.addAll(g.row([
      PosColumn(
          text: (birReady || order.isScPwd) ? 'AMOUNT DUE' : 'TOTAL',
          width: 6,
          styles: PosStyles(fontType: font, bold: true, height: PosTextSize.size2)),
      PosColumn(
          text: _peso(order.totalCents),
          width: 6,
          styles: PosStyles(fontType: font,
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          )),
    ]));
    bytes.addAll(g.hr());

    // ─── VAT-exempt disclosure (Senior / PWD) ───
    if (order.isScPwd) {
      final sub = order.subtotalCents;
      final net = tenant.vatRegistered ? (sub / 1.12).round() : sub;
      bytes.addAll(_kv(g, 'VAT-Exempt Sales', _peso(net), font: font));
      bytes.addAll(_kv(g, 'VAT Amount', _peso(0), font: font));
      bytes.addAll(g.text('*** VAT EXEMPT SALE ***',
          styles:
              PosStyles(fontType: font, align: PosAlign.center, bold: true)));
      final who = order.scPwdType == 'senior' ? 'SC' : 'PWD';
      bytes.addAll(g.text(_san('$who Name: ${order.scPwdName ?? ''}'),
          styles: PosStyles(fontType: font)));
      bytes.addAll(g.text(_san('$who ID No: ${order.scPwdId ?? ''}'),
          styles: PosStyles(fontType: font)));
      bytes.addAll(g.text('Signature: _____________________',
          styles: PosStyles(fontType: font)));
      bytes.addAll(g.hr());
    }

    // ─── Payment(s) ───
    for (final p in order.payments) {
      bytes.addAll(_kv(g, _paymentLabel(p.method), _peso(p.amountCents), font: font));
      if (p.tenderedCents != null && p.method == o.OrderPaymentMethod.cash) {
        bytes.addAll(_kv(g, '  Tendered', _peso(p.tenderedCents!), font: font));
        if (p.changeCents != null) {
          bytes.addAll(_kv(g, '  Change', _peso(p.changeCents!), font: font));
        }
      }
      if ((p.reference ?? '').isNotEmpty) {
        bytes.addAll(g.text(_san('  Ref: ${p.reference}')));
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
            g.text(_san(line), styles: PosStyles(fontType: font, align: headerAlign, bold: true)));
      }
    } else {
      bytes.addAll(g.text('Thank you - please come again!',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    }
    // ─── BIR footer ───
    if (birReady) {
      bytes.addAll(g.feed(1));
      bytes.addAll(g.text('This serves as your Sales Invoice',
          styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
      if (!tenant.vatRegistered) {
        bytes.addAll(g.text('THIS DOCUMENT IS NOT VALID',
            styles: PosStyles(fontType: font, align: PosAlign.center)));
        bytes.addAll(g.text('FOR CLAIM OF INPUT TAX',
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
      bytes.addAll(g.feed(1));
      bytes.addAll(g.text('Acquired from: Prestige POS',
          styles: PosStyles(fontType: font, align: PosAlign.center)));
      if ((tenant.birAccreditationNo ?? '').trim().isNotEmpty) {
        bytes.addAll(g.text(_san('Accred No: ${tenant.birAccreditationNo}'),
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
      if ((tenant.ptuNumber ?? '').trim().isNotEmpty) {
        bytes.addAll(g.text(_san('PTU No: ${tenant.ptuNumber}'),
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
      if ((tenant.ptuValidUntil ?? '').trim().isNotEmpty) {
        bytes.addAll(g.text(_san('Valid until: ${tenant.ptuValidUntil}'),
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
      bytes.addAll(g.feed(1));
      bytes.addAll(g.text('THIS INVOICE SHALL BE VALID FOR',
          styles: PosStyles(fontType: font, align: PosAlign.center)));
      bytes.addAll(g.text('FIVE (5) YEARS FROM PTU DATE.',
          styles: PosStyles(fontType: font, align: PosAlign.center)));
    } else if (official) {
      bytes.addAll(g.text('This serves as your Sales Invoice.',
          styles: PosStyles(fontType: font, align: PosAlign.center)));
    }
    bytes.addAll(_endFeed(g, tenant.printTailLines));
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
    const font = PosFontType.fontA;

    bytes.addAll(g.reset());

    bytes.addAll(g.text('ORDER',
        styles: PosStyles(fontType: font, 
          align: PosAlign.center,
          bold: true,
        )));
    bytes.addAll(g.text('#${order.orderNumber.toString().padLeft(4, '0')}',
        styles: PosStyles(fontType: font, 
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size3,
          width: PosTextSize.size3,
        )));
    bytes.addAll(g.text(_fmtDateTime(order.paidAt ?? order.createdAt),
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    if ((order.customerName ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text(_san('For: ${order.customerName}'),
          styles: PosStyles(fontType: font, 
            align: PosAlign.center,
            bold: true,
          )));
    }
    bytes.addAll(g.hr(ch: '='));

    for (final line in order.lines) {
      bytes.addAll(g.text(
        '${line.quantity}× ${line.name}',
        styles: PosStyles(fontType: font, 
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
            bytes.addAll(g.text(_san('  · ${entry.key}: ${entry.value}'),
                styles: PosStyles(fontType: font, bold: true)));
          }
        }
        final addOns = mods['add_ons'];
        if (addOns is List) {
          for (final a in addOns) {
            if (a is Map) {
              bytes.addAll(g.text(_san('  + ${a['quantity']}× ${a['name']}'),
                  styles: PosStyles(fontType: font, bold: true)));
            }
          }
        }
      }
      bytes.addAll(g.feed(1));
    }

    if ((order.notes ?? '').trim().isNotEmpty) {
      bytes.addAll(g.hr());
      bytes.addAll(g.text('Notes:',
          styles: PosStyles(fontType: font, bold: true)));
      bytes.addAll(g.text(_san(order.notes!.trim())));
    }

    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }

  /// Tiny test print used by the printer setup screen to confirm a printer is
  /// connected and the paper width is right.
  static Future<List<int>> testTicket({
    required Tenant tenant,
    required PrinterConfig printer,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];
    final font =
        tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA;
    bytes.addAll(g.reset());
    bytes.addAll(g.text(_san(tenant.businessName),
        styles: PosStyles(fontType: font, 
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )));
    bytes.addAll(g.feed(1));
    bytes.addAll(g.text('Printer connected!',
        styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    bytes.addAll(g.text('Prestige POS test print',
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    bytes.addAll(g.text('${printer.paperWidth}mm paper',
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    bytes.addAll(g.feed(1));
    bytes.addAll(g.hr());
    bytes.addAll(g.text('ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    bytes.addAll(g.text('0123456789  P \$ % &',
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    bytes.addAll(g.feed(3));
    bytes.addAll(g.cut());
    return bytes;
  }

  /// Sales report (X-reading style) — totals for a period, no cash-drawer
  /// reconciliation. Used for "today's sales".
  static Future<List<int>> salesReport({
    required Tenant tenant,
    required PrinterConfig printer,
    required String title,
    required ShiftTotals totals,
    String? subtitle,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];
    final font =
        tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA;

    bytes.addAll(g.reset());
    bytes.addAll(g.text(_san(tenant.businessName),
        styles: PosStyles(
            fontType: font,
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2)));
    bytes.addAll(g.text(title,
        styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    if (subtitle != null && subtitle.isNotEmpty) {
      bytes.addAll(g.text(_san(subtitle),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
    }
    bytes.addAll(g.text(_fmtDateTime(DateTime.now()),
        styles: PosStyles(fontType: font, align: PosAlign.center)));
    bytes.addAll(g.hr());
    bytes.addAll(_kv(g, 'Cash', _peso(totals.cashSalesCents), font: font));
    bytes.addAll(_kv(g, 'Card', _peso(totals.cardSalesCents), font: font));
    bytes.addAll(_kv(g, 'Other', _peso(totals.otherSalesCents), font: font));
    bytes.addAll(g.hr(ch: '='));
    bytes.addAll(g.row([
      PosColumn(
          text: 'TOTAL SALES',
          width: 7,
          styles: PosStyles(fontType: font, bold: true)),
      PosColumn(
          text: _peso(totals.totalSalesCents),
          width: 5,
          styles: PosStyles(
              fontType: font, align: PosAlign.right, bold: true)),
    ]));
    bytes.addAll(_kv(g, 'Orders', '${totals.orderCount}', font: font));
    bytes.addAll(g.hr());
    bytes.addAll(_endFeed(g, tenant.printTailLines));
    return bytes;
  }

  /// Z-Reading — the end-of-shift cash-up report.
  static Future<List<int>> zReading({
    required CashierShift shift,
    required Tenant tenant,
    required PrinterConfig printer,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];
    final font =
        tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA;

    bytes.addAll(g.reset());
    bytes.addAll(g.text(_san(tenant.businessName),
        styles: PosStyles(
            fontType: font,
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2)));
    bytes.addAll(g.text('Z-READING',
        styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    bytes.addAll(g.hr());
    bytes.addAll(
        g.text('Opened:  ${_fmtDateTime(shift.openedAt)}', styles: PosStyles(fontType: font)));
    if (shift.closedAt != null) {
      bytes.addAll(g.text('Closed:  ${_fmtDateTime(shift.closedAt!)}',
          styles: PosStyles(fontType: font)));
    }
    if ((shift.openedByName ?? '').isNotEmpty) {
      bytes.addAll(g.text(_san('Cashier: ${shift.openedByName}'),
          styles: PosStyles(fontType: font)));
    }
    bytes.addAll(g.hr());
    bytes.addAll(_kv(g, 'Beginning money', _peso(shift.openingFloatCents),
        font: font));
    bytes.addAll(
        _kv(g, 'Cash sales', _peso(shift.cashSalesCents ?? 0), font: font));
    bytes.addAll(_kv(g, 'Expected cash', _peso(shift.expectedCashCents ?? 0),
        font: font));
    bytes.addAll(_kv(g, 'Counted cash', _peso(shift.countedCashCents ?? 0),
        font: font));
    final over = shift.overShortCents ?? 0;
    bytes.addAll(_kv(
        g,
        over == 0 ? 'Balanced' : (over > 0 ? 'OVER' : 'SHORT'),
        _peso(over.abs()),
        font: font));
    bytes.addAll(g.hr(ch: '='));
    bytes.addAll(g.row([
      PosColumn(
          text: 'TOTAL SALES',
          width: 7,
          styles: PosStyles(fontType: font, bold: true)),
      PosColumn(
          text: _peso(shift.totalSalesCents ?? 0),
          width: 5,
          styles: PosStyles(
              fontType: font, align: PosAlign.right, bold: true)),
    ]));
    bytes.addAll(_kv(g, 'Orders', '${shift.orderCount ?? 0}', font: font));

    // ─── BIR accumulated grand total (non-resettable) ───
    final beg = shift.beginningGtCents;
    final end = shift.endingGtCents;
    if (beg != null || end != null) {
      bytes.addAll(g.hr());
      if (shift.zCounter != null) {
        bytes.addAll(
            _kv(g, 'Reset (Z) counter', '${shift.zCounter}', font: font));
      }
      bytes.addAll(_kv(g, 'Beginning GT', _peso(beg ?? 0), font: font));
      bytes.addAll(_kv(g, 'Ending GT', _peso(end ?? 0), font: font));
      if (beg != null && end != null) {
        bytes.addAll(
            _kv(g, 'Net sales (GT diff)', _peso(end - beg), font: font));
      }
    }
    // BIR machine identity (when configured).
    if ((tenant.tin ?? '').trim().isNotEmpty) {
      bytes.addAll(g.hr());
      bytes.addAll(g.text(
          _san('TIN: ${tenant.tin}  Branch: ${tenant.branchCode}'),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
      final idb = <String>[];
      if ((tenant.birMin ?? '').trim().isNotEmpty) {
        idb.add('MIN ${tenant.birMin}');
      }
      if ((tenant.birSerial ?? '').trim().isNotEmpty) {
        idb.add('SN ${tenant.birSerial}');
      }
      if (idb.isNotEmpty) {
        bytes.addAll(g.text(_san(idb.join('  ')),
            styles: PosStyles(fontType: font, align: PosAlign.center)));
      }
    }
    bytes.addAll(g.hr());
    bytes.addAll(_endFeed(g, tenant.printTailLines));
    return bytes;
  }

  /// Barista ticket — drinks only, no prices, big text. Routed to the bar.
  static Future<List<int>> barista({
    required o.Order order,
    required PrinterConfig printer,
    int template = 1,
    int tailLines = 2,
    PosFontType font = PosFontType.fontA,
  }) =>
      _prepTicket(
        order: order,
        printer: printer,
        title: 'BARISTA',
        lines: order.lines.where((l) => _isDrink(l.categoryName)).toList(),
        template: template,
        tailLines: tailLines,
        font: font,
      );

  /// Kitchen ticket — food only (excludes drinks + retail/service), no prices.
  static Future<List<int>> kitchenFood({
    required o.Order order,
    required PrinterConfig printer,
    int template = 1,
    int tailLines = 2,
    PosFontType font = PosFontType.fontA,
  }) =>
      _prepTicket(
        order: order,
        printer: printer,
        title: 'KITCHEN',
        lines: order.lines
            .where((l) =>
                !_isDrink(l.categoryName) && !_isRetailOrService(l.categoryName))
            .toList(),
        template: template,
        tailLines: tailLines,
        font: font,
      );

  /// True if [order] has any drink line (so a Barista ticket is worth offering).
  static bool hasDrinks(o.Order order) =>
      order.lines.any((l) => _isDrink(l.categoryName));

  /// True if [order] has any food line (so a Kitchen ticket is worth offering).
  static bool hasFood(o.Order order) => order.lines.any((l) =>
      !_isDrink(l.categoryName) && !_isRetailOrService(l.categoryName));

  /// Shared prep-ticket layout: big order number, big item names + mods, no
  /// prices. Used by both the barista and kitchen tickets.
  static Future<List<int>> _prepTicket({
    required o.Order order,
    required PrinterConfig printer,
    required String title,
    required List<o.OrderLine> lines,
    int template = 1,
    int tailLines = 2,
    PosFontType font = PosFontType.fontA,
  }) async {
    final profile = await CapabilityProfile.load();
    final size = printer.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final g = Generator(size, profile);
    final bytes = <int>[];

    // 1 = Standard, 2 = Minimal (# + items only, tight), 3 = Detailed (adds a
    // [ ] checkbox per item the cook can tick off).
    final minimal = template == 2;
    final detailed = template == 3;

    bytes.addAll(g.reset());
    bytes.addAll(g.text(title,
        styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
    bytes.addAll(g.text('#${order.orderNumber.toString().padLeft(4, '0')}',
        styles: PosStyles(fontType: font, 
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )));
    if (!minimal) {
      bytes.addAll(g.text(_fmtDateTime(order.paidAt ?? order.createdAt),
          styles: PosStyles(fontType: font, align: PosAlign.center)));
      if ((order.customerName ?? '').trim().isNotEmpty) {
        bytes.addAll(g.text(_san('For: ${order.customerName}'),
            styles: PosStyles(fontType: font, align: PosAlign.center, bold: true)));
      }
    }
    bytes.addAll(g.hr(ch: '='));

    for (final line in lines) {
      final prefix = detailed ? '[ ] ' : '';
      // Normal receipt-size text (was double-height — too big / wasteful).
      bytes.addAll(g.text(_san('$prefix${line.quantity}x ${line.name}'),
          styles: PosStyles(fontType: font, bold: true)));
      final mods = line.modifiers;
      if (mods != null) {
        final opts = mods['options'];
        if (opts is Map) {
          for (final entry in opts.entries) {
            bytes.addAll(g.text(_san('  - ${entry.key}: ${entry.value}'),
                styles: PosStyles(fontType: font, bold: true)));
          }
        }
        final addOns = mods['add_ons'];
        if (addOns is List) {
          for (final a in addOns) {
            if (a is Map) {
              bytes.addAll(g.text(_san('  + ${a['quantity']}x ${a['name']}'),
                  styles: PosStyles(fontType: font, bold: true)));
            }
          }
        }
      }
      // Only Detailed adds a separating line between items; Standard/Minimal
      // pack tight to save paper.
      if (detailed) bytes.addAll(g.feed(1));
    }

    if (!minimal && (order.notes ?? '').trim().isNotEmpty) {
      bytes.addAll(g.hr());
      bytes.addAll(g.text('Notes:', styles: PosStyles(fontType: font, bold: true)));
      bytes.addAll(g.text(_san(order.notes!.trim())));
    }

    bytes.addAll(_endFeed(g, tailLines));
    return bytes;
  }

  static const _drinkCats = {
    'coffee', 'tea', 'soda', 'milk tea', 'milktea', 'smoothie', 'frappe',
    'frappé', 'juice', 'drink', 'drinks', 'beverage', 'beverages', 'espresso',
    'shakes', 'shake',
  };
  static const _retailCats = {
    'books', 'book', 'merch', 'merchandise', 'retail', 'sticker', 'stickers',
    'painting', 'paintings', 'flower', 'flowers', 'gift', 'gifts', 'toy',
    'toys', 'membership', 'memberships', 'day pass', 'hot desk', 'meeting room',
  };

  static bool _isDrink(String? category) {
    final c = (category ?? '').toLowerCase().trim();
    if (c.isEmpty) return false;
    return _drinkCats.contains(c) || _drinkCats.any((d) => c.contains(d));
  }

  static bool _isRetailOrService(String? category) {
    final c = (category ?? '').toLowerCase().trim();
    if (c.isEmpty) return false;
    return _retailCats.contains(c) || _retailCats.any((r) => c.contains(r));
  }

  // ─── helpers ──────────────────────────────────────────────────────

  static List<int> _kv(Generator g, String k, String v,
      {bool fadedFirstCol = false, PosFontType font = PosFontType.fontA}) {
    return g.row([
      PosColumn(
        text: k,
        width: 8,
        styles: PosStyles(fontType: font, bold: !fadedFirstCol),
      ),
      PosColumn(
        text: v,
        width: 4,
        styles: PosStyles(fontType: font, align: PosAlign.right),
      ),
    ]);
  }

  /// Final paper advance + cut. [lines] is the owner's tail-spacing setting
  /// (0 = none) — keeps portable printers without an auto-cutter from wasting
  /// paper between tickets.
  static List<int> _endFeed(Generator g, int lines) {
    final out = <int>[];
    final n = lines.clamp(0, 8);
    if (n > 0) out.addAll(g.feed(n));
    out.addAll(g.cut());
    return out;
  }

  static String _peso(int cents) {
    final pesos = cents / 100;
    // Thermal printers encode Latin-1 and can't render the ₱ glyph, so we
    // print "P" for pesos on receipts.
    return 'P${pesos.toStringAsFixed(2)}';
  }

  /// Makes text safe for the printer's Latin-1 encoder. Maps the few common
  /// non-Latin-1 glyphs the POS produces to ASCII, and replaces anything else
  /// outside Latin-1 with '?' so building a ticket never throws.
  static String _san(String s) {
    final mapped = s
        .replaceAll('₱', 'P')
        .replaceAll('×', 'x') // printer renders × as '#'
        .replaceAll('·', '-') // printer renders · as 'ⁿ'
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('…', '...');
    final buf = StringBuffer();
    for (final r in mapped.runes) {
      buf.writeCharCode(r <= 0xFF ? r : 0x3F); // '?'
    }
    return buf.toString();
  }

  static String _fmtDateTime(DateTime dt) {
    final d = dt.toLocal(); // DB times are UTC — show in the store's timezone
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final mm = d.minute.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${months[d.month - 1]} $dd, ${d.year}  $h12:$mm $ampm';
  }

  static String _paymentLabel(o.OrderPaymentMethod m) => switch (m) {
        o.OrderPaymentMethod.cash => 'Cash',
        o.OrderPaymentMethod.gcash => 'GCash',
        o.OrderPaymentMethod.paymaya => 'Maya',
        o.OrderPaymentMethod.card => 'Card',
        o.OrderPaymentMethod.bankTransfer => 'Bank',
        o.OrderPaymentMethod.qrPh => 'QR Ph',
        _ => 'Other',
      };
}

/// Tiny wrapper so existing callers can keep using `Uint8List` without
/// casting. ESC/POS generators return `List<int>`; sockets want bytes.
extension EscPosBytesX on List<int> {
  Uint8List asBytes() => Uint8List.fromList(this);
}
