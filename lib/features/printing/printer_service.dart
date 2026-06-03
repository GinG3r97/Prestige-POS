import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../models/order.dart' as o;
import '../../models/printer_config.dart';
import '../../models/tenant.dart';
import 'receipt_builder.dart';

/// Outcome of a single print attempt. Used by the tender flow to decide
/// whether to surface a toast — printing is always fire-and-forget, never
/// blocks the order from completing.
class PrintResult {
  PrintResult.ok(this.printerName)
      : success = true,
        error = null;
  PrintResult.fail(this.printerName, this.error) : success = false;

  final String printerName;
  final bool success;
  final String? error;
}

/// Pure-Dart printer client. Opens a TCP socket to `host:port` and writes
/// the ESC/POS byte stream. Suitable for any LAN-connected thermal
/// printer (Xprinter, Goojprt, Epson TM-T20II, Star, etc.) that listens
/// on port 9100 — that's almost every café printer in PH.
///
/// Bluetooth is Phase 2 — for now [print] short-circuits with an error
/// for `PrinterTransport.bluetooth`.
class PrinterService {
  PrinterService._();

  /// Connect timeout. Most thermal printers respond in <100ms on the
  /// local network; if it takes longer than this the printer is offline
  /// or the IP is wrong, no point waiting.
  static const _connectTimeout = Duration(seconds: 3);

  /// Send raw ESC/POS bytes to a printer. Returns a `PrintResult` so
  /// callers can show a per-printer toast (fail one, succeed another).
  static Future<PrintResult> sendBytes(
    PrinterConfig printer,
    List<int> bytes,
  ) async {
    if (printer.transport != PrinterTransport.lan) {
      return PrintResult.fail(
        printer.name,
        'Bluetooth printers aren\'t supported yet — configure a LAN '
            'printer for now.',
      );
    }
    final host = printer.host?.trim();
    if (host == null || host.isEmpty) {
      return PrintResult.fail(
        printer.name,
        'No IP / hostname set — open Maintenance → Printers and add one.',
      );
    }
    Socket? socket;
    try {
      socket = await Socket.connect(host, printer.port,
          timeout: _connectTimeout);
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      // Tiny grace period so the printer drains its buffer before we
      // close — some Xprinter firmwares truncate the last line otherwise.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return PrintResult.ok(printer.name);
    } on SocketException catch (e) {
      return PrintResult.fail(
        printer.name,
        'Could not reach ${printer.host}:${printer.port} — '
            '${e.message}. Check the printer is on and on the same Wi-Fi.',
      );
    } on TimeoutException {
      return PrintResult.fail(
        printer.name,
        'Timed out connecting to ${printer.host}:${printer.port}. '
            'Is the printer on the same network?',
      );
    } catch (e) {
      return PrintResult.fail(printer.name, 'Print failed: $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {/* socket already closed */}
    }
  }

  /// Build + print a customer receipt. Returns the result so callers can
  /// react (toast on fail, etc.). Picks the appropriate paper width from
  /// the printer config.
  static Future<PrintResult> printReceipt({
    required PrinterConfig printer,
    required o.Order order,
    required Tenant tenant,
    String? footerMessage,
  }) async {
    final bytes = await ReceiptBuilder.bir(
      order: order,
      tenant: tenant,
      printer: printer,
      footerMessage: footerMessage,
      logoBytes: await _fetchLogo(tenant.logoUrl),
    );
    return sendBytes(printer, bytes);
  }

  /// Best-effort fetch of the store logo for the receipt header. Returns null
  /// (so the receipt just prints without a logo) on any failure — printing
  /// must never break because an image couldn't be downloaded.
  static Future<Uint8List?> _fetchLogo(String? url) async {
    if (url == null || url.isEmpty) return null;
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Build + print a kitchen / bar slip. No prices, big bold text.
  static Future<PrintResult> printKitchenSlip({
    required PrinterConfig printer,
    required o.Order order,
  }) async {
    final bytes = await ReceiptBuilder.kitchen(
      order: order,
      printer: printer,
    );
    return sendBytes(printer, bytes);
  }

  /// Quick "Test print" used by Maintenance to verify a printer config.
  /// Prints a tiny header + cut so the owner sees something pop out the
  /// printer without needing a real order.
  static Future<PrintResult> testPrint(PrinterConfig printer) async {
    final bytes = await ReceiptBuilder.bir(
      order: o.Order(
        id: '00000000-0000-0000-0000-000000000000',
        tenantId: '',
        orderNumber: 0,
        status: o.OrderStatus.paid,
        subtotalCents: 0,
        totalCents: 0,
        createdAt: DateTime.now(),
        paidAt: DateTime.now(),
      ),
      tenant: Tenant(
        id: '',
        businessName: 'TEST PRINT',
        address: 'Connection looks good',
      ),
      printer: printer,
      footerMessage: 'If you see this, your printer is configured correctly.',
    );
    return sendBytes(printer, bytes);
  }
}
