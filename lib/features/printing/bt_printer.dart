import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// A discovered Bluetooth printer (name + address). On Android the address is
/// the MAC; on iOS it's the BLE peripheral UUID — either way it's the handle
/// we connect with.
class BtDevice {
  final String name;
  final String address;
  const BtDevice(this.name, this.address);
}

/// Thin wrapper over `print_bluetooth_thermal` so the rest of the app doesn't
/// depend on the package's API directly. Handles BLE on iOS and Classic/BLE on
/// Android. All methods swallow errors and return safe defaults — printing is
/// best-effort and must never crash the POS.
class BtPrinter {
  BtPrinter._();

  /// Whether Bluetooth is powered on.
  static Future<bool> isEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Android: paired devices. iOS: nearby BLE devices found by a short scan.
  static Future<List<BtDevice>> scan() async {
    try {
      final list = await PrintBluetoothThermal.pairedBluetooths;
      return [for (final d in list) BtDevice(d.name, d.macAdress)];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  /// Connects to [address], dropping any prior connection first.
  static Future<bool> connect(String address) async {
    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
      return await PrintBluetoothThermal.connect(macPrinterAddress: address);
    } catch (_) {
      return false;
    }
  }

  /// Ensures a connection to [address], then writes [bytes]. Returns true on
  /// success.
  static Future<bool> printBytes(String address, List<int> bytes) async {
    try {
      if (!await PrintBluetoothThermal.connectionStatus) {
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
        if (!ok) return false;
      }
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {/* already disconnected */}
  }
}
