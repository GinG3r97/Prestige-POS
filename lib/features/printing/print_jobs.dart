import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/order.dart' as o;
import '../../models/printer_config.dart';
import '../../models/shift.dart';
import '../../models/tenant.dart';
import 'bt_printer.dart';
import 'printer_service.dart';
import 'receipt_builder.dart';

/// High-level print jobs — build the ESC/POS bytes for a given document and
/// send them to the configured printer over the right transport (Bluetooth
/// for the PT-210 etc., or LAN). Returns true on success; never throws.
class PrintJobs {
  PrintJobs._();

  static Future<bool> _send(PrinterConfig config, List<int> bytes) async {
    if (config.transport == PrinterTransport.bluetooth) {
      final addr = config.bluetoothId;
      if (addr == null || addr.isEmpty) return false;
      return BtPrinter.printBytes(addr, bytes);
    }
    final res = await PrinterService.sendBytes(config, bytes);
    return res.success;
  }

  /// Customer receipt (prices, totals, payment, header/footer).
  static Future<bool> receipt({
    required o.Order order,
    required Tenant tenant,
    required PrinterConfig config,
    String? footerMessage,
    bool reprint = false,
  }) async {
    final bytes = await ReceiptBuilder.bir(
        order: order,
        tenant: tenant,
        printer: config,
        footerMessage: footerMessage,
        reprint: reprint);
    return _send(config, bytes);
  }

  /// Barista prep ticket (drinks only, no prices).
  static Future<bool> barista({
    required o.Order order,
    required Tenant tenant,
    required PrinterConfig config,
  }) async {
    final bytes = await ReceiptBuilder.barista(
      order: order,
      printer: config,
      template: tenant.ticketTemplate,
      tailLines: tenant.printTailLines,
      font: tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA,
    );
    return _send(config, bytes);
  }

  /// Sales report (e.g. today's sales) — totals only, no cash reconciliation.
  static Future<bool> salesReport({
    required Tenant tenant,
    required PrinterConfig config,
    required String title,
    required ShiftTotals totals,
    String? subtitle,
  }) async {
    final bytes = await ReceiptBuilder.salesReport(
        tenant: tenant,
        printer: config,
        title: title,
        totals: totals,
        subtitle: subtitle);
    return _send(config, bytes);
  }

  /// Z-Reading end-of-shift report.
  static Future<bool> zReading({
    required CashierShift shift,
    required Tenant tenant,
    required PrinterConfig config,
  }) async {
    final bytes = await ReceiptBuilder.zReading(
        shift: shift, tenant: tenant, printer: config);
    return _send(config, bytes);
  }

  /// Kitchen prep ticket (food only, no prices).
  static Future<bool> kitchen({
    required o.Order order,
    required Tenant tenant,
    required PrinterConfig config,
  }) async {
    final bytes = await ReceiptBuilder.kitchenFood(
      order: order,
      printer: config,
      template: tenant.ticketTemplate,
      tailLines: tenant.printTailLines,
      font: tenant.printFont == 'b' ? PosFontType.fontB : PosFontType.fontA,
    );
    return _send(config, bytes);
  }
}
