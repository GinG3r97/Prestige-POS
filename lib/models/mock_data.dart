import 'employee.dart';

/// Tiny fallback data used before the real tenant loads (e.g. the branch
/// picker on the top bar). Everything else is DB-backed.
class MockData {
  static final branches = [
    Branch(name: 'Main Branch'),
    Branch(name: 'Tagaytay'),
  ];
}
