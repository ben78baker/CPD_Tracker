import 'dart:async';

import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_rehearsal_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rehearsal blocks back navigation until the actual task finishes',
    (tester) async {
      final completion = Completer<CpdMigrationCoordinator>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MigrationRehearsalPage(
                      openAttempt: (_, _) => completion.future,
                    ),
                  ),
                ),
                child: const Text('Open test route'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open test route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run rehearsal'));
      await tester.pump();
      expect(
        find.text('Keep this screen open while the check runs.'),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(MigrationRehearsalPage), findsOneWidget);
      completion.completeError(StateError('Synthetic failure'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open test route'), findsOneWidget);
    },
  );

  testWidgets('French preparation works on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            size: Size(320, 640),
          ),
          child: child!,
        ),
        home: MigrationRehearsalPage(
          openAttempt: (_, _) async => throw StateError('No action expected'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Essai de stockage'), findsOneWidget);
    final start = find.text('Lancer l’essai');
    await tester.scrollUntilVisible(
      start,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
