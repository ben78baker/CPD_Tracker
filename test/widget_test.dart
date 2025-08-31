// Smoke test for CPD Tracker (robust against routing/semantics)
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cpd_tracker/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders Home (or at least an AppBar) without errors', (WidgetTester tester) async {
    // Seed SharedPreferences so app skips onboarding and shows Home
    SharedPreferences.setMockInitialValues({
      'professions': <String>['Test Profession'],
    });

    // Build the app
    await tester.pumpWidget(const MyApp(startOnboarding: false));

    // Let the first frame and microtasks complete
    await tester.pump();

    // There should be a MaterialApp and at least one AppBar
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AppBar), findsWidgets);

    // Prefer the exact Home title if present
    final cpdt = find.text('CPD Tracker');
    if (cpdt.evaluate().isNotEmpty) {
      expect(cpdt, findsOneWidget);
    }
  });
}
