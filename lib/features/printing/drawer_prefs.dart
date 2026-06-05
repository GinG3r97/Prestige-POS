import 'package:shared_preferences/shared_preferences.dart';

/// Device-local cash-drawer settings. The drawer pin is a hardware trait of the
/// physical station (which connector the drawer cable uses on the printer), so
/// it's stored per-device rather than synced — each till keeps its own value.
///
/// Pin 2 is the near-universal default; only a few drawers use pin 5.
class DrawerPrefs {
  DrawerPrefs._();

  static const _kPin5 = 'cash_drawer_pin5';

  /// True if the drawer is wired to connector pin 5 instead of pin 2.
  static Future<bool> usesPin5() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPin5) ?? false;
  }

  /// Persist the pin choice (false = pin 2, true = pin 5).
  static Future<void> setUsesPin5(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPin5, value);
  }
}
