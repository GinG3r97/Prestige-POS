import '../../models/order.dart' as o;
import '../../models/printer_config.dart';
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
  }) async {
    final bytes = await ReceiptBuilder.bir(
        order: order, tenant: tenant, printer: config, footerMessage: footerMessage);
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
    );
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
    );
    return _send(config, bytes);
  }
}
