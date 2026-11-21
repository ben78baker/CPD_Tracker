import 'dart:io';

import 'package:cpd_tracker/cpd_backup/backup_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets(
    'validation, cancellation and explicit confirmation are separate',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('backup_page_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final data = File(p.join(root.path, 'data'))
        ..writeAsStringSync('example\n');
      final file = File(p.join(root.path, 'backup'));
      final created = await tester.runAsync(
        () => const PortableArchive().write(
          files: {PortableArchive.rows: data},
          destination: file,
          created: DateTime.utc(2026, 11, 21),
          schema: 4,
          available: (_) async => 1024 * 1024,
        ),
      );
      var preparations = 0;
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('en'),
          theme: AppTheme.forAccent(AppAccent.purple),
          home: BackupPage(
            create: () async => (file: file, inspection: created!),
            chooseAndVerify: () async => (file: file, inspection: created!),
            share: (_, _) async {},
            prepareReplacement: (_) async => preparations++,
          ),
        ),
      );
      expect(find.text('Prepare replacement'), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Choose backup to verify'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backup verified'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Prepare replacement');
      await tester.scrollUntilVisible(confirm, 200);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(preparations, 0);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: confirm),
      );
      await tester.pumpAndSettle();
      expect(preparations, 1);
      expect(find.textContaining('Restore copy verified'), findsOneWidget);
    },
  );

  testWidgets('all six locale strings resolve with all eight app colours', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in AppLocalizations.supportedLocales) {
      for (final accent in AppAccent.values) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: AppTheme.forAccent(accent),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.7)),
              child: child!,
            ),
            home: BackupPage(
              create: () async => throw StateError('unused'),
              chooseAndVerify: () async => null,
              share: (_, _) async {},
              prepareReplacement: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(BackupPage));
        final local = AppLocalizations.of(context)!;
        expect(local.localeName, locale.languageCode);
        expect(find.text(local.p8Title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
