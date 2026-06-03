import 'package:flutter/foundation.dart';

/// Drives the auto-collapsing floating bottom nav. Listens for activity
/// signals from the shell (scroll, pointer down on content) and collapses
/// itself; the compact icon is the only re-entry point.
class NavController extends ChangeNotifier {
  bool _expanded = true;
  bool get expanded => _expanded;

  /// When false, [poke] is a no-op — the nav stays expanded regardless of
  /// scroll or content taps. Toggled from Settings.
  bool _autoCollapse = true;
  bool get autoCollapse => _autoCollapse;

  void setAutoCollapse(bool value) {
    if (_autoCollapse == value) return;
    _autoCollapse = value;
    // Turning it off mid-collapse: expand back so the user isn't stuck.
    if (!value && !_expanded) _expanded = true;
    notifyListeners();
  }

  /// Activity ping from the content area — scrolling, tapping a product,
  /// adjusting the cart, etc. Collapses if currently expanded; no-op when
  /// already collapsed so we don't churn animations on every pixel of scroll.
  void poke() {
    if (!_autoCollapse) return;
    if (_expanded) {
      _expanded = false;
      notifyListeners();
    }
  }

  void toggle() {
    _expanded = !_expanded;
    notifyListeners();
  }

  void expand() {
    if (!_expanded) {
      _expanded = true;
      notifyListeners();
    }
  }
}
