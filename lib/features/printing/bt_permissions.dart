import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Requests the Android-12+ runtime Bluetooth permissions that
/// `print_bluetooth_thermal` needs but does not request on its own.
///
/// On iOS this is a no-op (returns true) — there the plugin's BLE access
/// triggers the system prompt via `NSBluetoothAlwaysUsageDescription`. The
/// actual request is handled natively in `MainActivity.kt`.
class BtPermissions {
  BtPermissions._();

  static const _channel = MethodChannel('prestige.pos/bt_permissions');

  /// Ensures BLUETOOTH_CONNECT / BLUETOOTH_SCAN are granted on Android 12+.
  /// Returns true if granted (or not required on this platform / OS version).
  /// Never throws — printer setup must stay resilient.
  static Future<bool> ensure() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('ensure');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }
}
