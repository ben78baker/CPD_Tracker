import 'dart:async';

import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_recovery_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget page, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  theme: AppTheme.forAccent(AppAccent.teal),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.8)),
    child: child!,
  ),
  home: page,
);

void main() {
  testWidgets('progress is indeterminate and Continue needs adoption', (
    tester,
  ) async {
    final result = Completer<StartupAuthority>();
    var opened = 0;
    await tester.pumpWidget(
      _host(
        MigrationRecoveryPage(
          prepare: (notify) async {
            await notify(const MigrationReport(MigrationPhase.verifying));
            return result.future;
          },
          onReady: () => opened++,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Preparing your records'), findsOneWidget);
    result.complete(
      const StartupAuthority(
        StoreAuthority.recording,
        AuthorityReason.activated,
        RecoveryCopyState.manifestVerified,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    expect(opened, 1);
  });

  testWidgets('assisted state copies only a diagnostic summary', (
    tester,
  ) async {
    Object? copied;
    final platform = tester.binding.defaultBinaryMessenger;
    platform.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments;
      return null;
    });
    addTearDown(
      () => platform.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final result = Completer<StartupAuthority>();
    await tester.pumpWidget(
      _host(
        MigrationRecoveryPage(
          prepare: (_) => result.future,
          onReady: () => fail('An uncertain store cannot open.'),
        ),
      ),
    );
    result.complete(
      const StartupAuthority(
        StoreAuthority.recovery,
        AuthorityReason.interruptedHandoff,
        RecoveryCopyState.manifestVerified,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Your records need a recovery check'), findsOneWidget);
    final copy = find.text('Copy recovery details');
    await tester.scrollUntilVisible(
      copy,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pump();
    expect(copied, {
      'text':
          'CPD migration recovery\nStartup: interruptedHandoff\n'
          'Recovery copy: manifestVerified',
    });
    expect(tester.takeException(), isNull);
  });
}
