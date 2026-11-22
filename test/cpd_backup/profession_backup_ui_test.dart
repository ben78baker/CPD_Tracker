import 'dart:io';

import 'package:cpd_tracker/cpd_backup/profession_backup_page.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedRepository implements SqliteRecordingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('restore entry fits all locales and colours at large text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp;
    final store = ProfessionCreationStore(
      _UnusedRepository(),
      templates: {},
      reportRules: {},
    );
    final actions = ProfessionBackupActions(
      backups: SqliteCollectionBackup(available: (_) async => 0),
      temporary: root,
      originals: ManagedAttachmentFiles(root),
      pick: () async => null,
      share: (_, _) async {},
    );
    for (final locale in AppLocalizations.supportedLocales) {
      for (final accent in AppAccent.values) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey((locale, accent)),
            locale: locale,
            theme: AppTheme.forAccent(accent),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.7)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => actions.open(context, store),
                    child: const Text('Test entry'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test entry'));
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(Scaffold).last),
        )!;
        expect(find.text(strings.pbRestore), findsOneWidget);
        expect(find.text(strings.p8Choose), findsOneWidget);
        expect(find.text(strings.pbAddRestored), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
