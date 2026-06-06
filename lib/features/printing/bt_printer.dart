import 'dart:async';
import 'dart:io' show Platform;

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// A discovered Bluetooth printer (name + address). On Android the address is
/// the MAC; on iOS it's the BLE peripheral UUID — either way it's the handle
/// we connect with.
class BtDevice {
  final String name;
  final String address;
  const BtDevice(this.name, this.address);
}

/// iOS CoreBluetooth identifies peripherals by UUID. The native plugin runs
/// `UUID(uuidString: address)!` and force-unwraps — so handing it anything that
/// isn't a valid UUID (e.g. an Android-style MAC, or a stale/blank saved value)
/// crashes the whole app with a Swift fatalError that Dart try/catch CANNOT
/// catch. The only safe defense is to never call connect with a bad value.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isConnectableAddress(String address) {
  final a = address.trim();
  if (a.isEmpty) return false;
  // Android uses MAC addresses (any non-empty handle is fine). iOS must be a
  // UUID or the native connect force-unwrap crashes the app.
  if (Platform.isIOS) return _uuidPattern.hasMatch(a);
  return true;
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

  /// Connects to [address], dropping any prior (possibly stale) connection
  /// first, then retrying a few times. The radio is often cold or the previous
  /// socket half-open after the printer slept / went out of range, so a single
  /// attempt frequently fails — these retries are what make reconnect reliable.
  static Future<bool> connect(String address) async {
    // Guard BEFORE touching the native plugin: a non-UUID address on iOS would
    // crash via force-unwrap (uncatchable from Dart). Bail safely instead.
    if (!_isConnectableAddress(address)) return false;
    try {
      // Tear down any prior connection first so a stale half-open socket can't
      // block a fresh connect. Guarded: the native disconnect crashes if
      // nothing is connected (see _safeDisconnect).
      await _safeDisconnect();
      await Future.delayed(const Duration(milliseconds: 350));

      for (var attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) {
          await Future.delayed(Duration(milliseconds: 400 + attempt * 350));
        }
        try {
          if (await PrintBluetoothThermal.connect(macPrinterAddress: address)) {
            return true;
          }
        } catch (_) {/* retry */}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Serializes print jobs — a thermal printer can only handle one at a time,
  // so concurrent writes (or a spammed button) corrupt output. Each call waits
  // for the previous to finish.
  static Future<bool> _chain = Future.value(true);

  /// Ensures a connection to [address], then writes [bytes]. Jobs run strictly
  /// one after another. Returns true on success.
  static Future<bool> printBytes(String address, List<int> bytes) {
    final prev = _chain;
    final completer = Completer<bool>();
    _chain = completer.future;
    prev.whenComplete(() async {
      bool result;
      try {
        result = await _write(address, bytes);
      } catch (_) {
        result = false;
      }
      completer.complete(result);
    });
    return completer.future;
  }

  static Future<bool> _write(String address, List<int> bytes) async {
    if (!_isConnectableAddress(address)) return false;
    // Reuse a live connection if there is one; otherwise (re)connect with
    // retries. `connect` already disconnects-then-retries for cold radios.
    var connected = false;
    try {
      connected = await PrintBluetoothThermal.connectionStatus;
    } catch (_) {/* treat as not connected */}
    if (!connected && !await connect(address)) return false;

    // First write attempt over the (possibly reused) connection.
    try {
      if (await PrintBluetoothThermal.writeBytes(bytes)) return true;
    } catch (_) {/* connection was likely stale — fall through to reconnect */}

    // The socket was dead despite a "connected" status — force a clean
    // reconnect and write once more before giving up.
    if (await connect(address)) {
      try {
        return await PrintBluetoothThermal.writeBytes(bytes);
      } catch (_) {/* give up */}
    }
    return false;
  }

  static Future<void> disconnect() async {
    await _safeDisconnect();
  }

  /// Disconnect ONLY when something is actually connected. The native iOS
  /// `disconnect` passes `connectedPeripheral` (an implicitly-unwrapped
  /// optional) straight to `cancelPeripheralConnection`; if nothing is
  /// connected it's nil and the app dies with a Swift fatalError that Dart
  /// try/catch cannot catch. `connectionStatus` is nil-safe, so gate on it —
  /// a true result means `connectedPeripheral` is non-nil and safe to cancel.
  static Future<void> _safeDisconnect() async {
    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
    } catch (_) {/* best effort */}
  }
}
