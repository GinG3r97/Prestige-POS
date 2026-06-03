/// How the app reaches a thermal printer. LAN is the common path for
/// café printers (Xprinter / Goojprt / Epson TM with Ethernet or Wi-Fi —
/// listen on TCP port 9100 by default). Bluetooth is Phase 2.
enum PrinterTransport { lan, bluetooth }

extension PrinterTransportX on PrinterTransport {
  String get dbValue => switch (this) {
        PrinterTransport.lan => 'lan',
        PrinterTransport.bluetooth => 'bluetooth',
      };

  String get label => switch (this) {
        PrinterTransport.lan => 'Network (LAN / Wi-Fi)',
        PrinterTransport.bluetooth => 'Bluetooth',
      };

  static PrinterTransport fromDb(String? v) => switch (v) {
        'bluetooth' => PrinterTransport.bluetooth,
        _ => PrinterTransport.lan,
      };
}

/// What the printer prints. Determines which template fires and which
/// kind of order events auto-route to it.
enum PrinterRole { receipt, kitchen, bar }

extension PrinterRoleX on PrinterRole {
  String get dbValue => switch (this) {
        PrinterRole.receipt => 'receipt',
        PrinterRole.kitchen => 'kitchen',
        PrinterRole.bar => 'bar',
      };

  String get label => switch (this) {
        PrinterRole.receipt => 'Customer receipt',
        PrinterRole.kitchen => 'Kitchen slip',
        PrinterRole.bar => 'Bar slip',
      };

  static PrinterRole fromDb(String? v) => switch (v) {
        'kitchen' => PrinterRole.kitchen,
        'bar' => PrinterRole.bar,
        _ => PrinterRole.receipt,
      };
}

class PrinterConfig {
  final String id;
  String name;
  PrinterRole role;
  PrinterTransport transport;
  /// LAN host (IP or hostname). Null for Bluetooth.
  String? host;
  /// LAN port. Defaults to 9100 (raw ESC/POS).
  int port;
  /// Bluetooth identifier (Phase 2).
  String? bluetoothId;
  /// 58 or 80 — mm.
  int paperWidth;
  /// True if this printer should fire automatically on payment complete.
  /// False = manual reprint only.
  bool autoPrint;
  int sortOrder;

  PrinterConfig({
    required this.id,
    required this.name,
    required this.role,
    this.transport = PrinterTransport.lan,
    this.host,
    this.port = 9100,
    this.bluetoothId,
    this.paperWidth = 58,
    this.autoPrint = true,
    this.sortOrder = 0,
  });

  /// Chars-per-line for monospace receipt layout. 58mm fits ~32 chars,
  /// 80mm fits ~48. ReceiptBuilder uses this to align prices to the
  /// right edge.
  int get charsPerLine => paperWidth == 80 ? 48 : 32;

  factory PrinterConfig.fromRow(Map<String, dynamic> row) => PrinterConfig(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? 'Printer',
        role: PrinterRoleX.fromDb(row['role'] as String?),
        transport: PrinterTransportX.fromDb(row['transport'] as String?),
        host: row['host'] as String?,
        port: (row['port'] as int?) ?? 9100,
        bluetoothId: row['bluetooth_id'] as String?,
        paperWidth: (row['paper_width'] as int?) ?? 58,
        autoPrint: (row['auto_print'] as bool?) ?? true,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );

  Map<String, dynamic> toRowPayload(String tenantId) => {
        'tenant_id': tenantId,
        'name': name.trim(),
        'role': role.dbValue,
        'transport': transport.dbValue,
        'host': host?.trim(),
        'port': port,
        'bluetooth_id': bluetoothId,
        'paper_width': paperWidth,
        'auto_print': autoPrint,
        'sort_order': sortOrder,
      };
}
