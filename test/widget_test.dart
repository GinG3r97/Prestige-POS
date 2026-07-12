// Minimal smoke test. The real app root (YosefPOSApp) boots Supabase and
// provider state, which isn't appropriate for a lightweight unit test, so this
// just verifies the test harness + a trivial widget render. Feature-level
// tests can be added per screen as needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('harness renders a basic widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Prestige Café'))),
    );
    expect(find.text('Prestige Café'), findsOneWidget);
  });
}
