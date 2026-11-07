import 'package:cpd_tracker/deleted_records_page.dart';
import 'package:cpd_tracker/global_search_page.dart';
import 'package:cpd_tracker/home_page.dart';
import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/widgets/tactile_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/profession_recovery_test.dart' show record;

Widget app(Widget page) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: page,
);

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'professions': ['Electrician'],
      'entries_json_list': [
        record(1, 'Electrician').toJson(),
        record(2, 'Electrician', deleted: true).toJson(),
      ],
    }),
  );

  testWidgets(
    'lists only deleted records with title, profession, date and restore',
    (tester) async {
      await tester.pumpWidget(app(const DeletedRecordsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Course 2'), findsOneWidget);
      expect(find.text('Course 1'), findsNothing);
      expect(find.text('Electrician · 15/01/2026'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Export'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('restore-record-2')),
          matching: find.text('Restore'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(find.text('No deleted records'), findsOneWidget);
      expect(
        (await EntryRepository().loadForProfession('Electrician')).length,
        2,
      );
    },
  );

  testWidgets(
    'missing profession recovery is explicit and cancellation changes nothing',
    (tester) async {
      await SettingsStore.instance.saveProfessions([]);
      await tester.pumpWidget(app(const DeletedRecordsPage()));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('restore-record-2')),
          matching: find.text('Restore'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('other saved, non-deleted records'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await SettingsStore.instance.loadProfessions(), isEmpty);
      expect((await EntryRepository().loadDeleted()).length, 1);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('restore-record-2')),
          matching: find.text('Restore'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(await SettingsStore.instance.loadActiveProfessions(), [
        'Electrician',
      ]);
      expect(
        (await EntryRepository().loadForProfession('Electrician')).length,
        2,
      );
    },
  );

  testWidgets(
    'home menu opens separate Deleted Records and reloads recovered profession',
    (tester) async {
      await SettingsStore.instance.saveProfessions([]);
      await tester.pumpWidget(app(const HomePage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-menu-action')));
      await tester.pumpAndSettle();
      expect(find.text('View Deleted Professions'), findsOneWidget);
      await tester.tap(find.text('Deleted Records'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('restore-record-2')),
          matching: find.text('Restore'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Restore'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Electrician'), findsOneWidget);
    },
  );

  testWidgets(
    'permanent profession deletion is disabled while restore remains available',
    (tester) async {
      await SettingsStore.instance.softDeleteProfession('Electrician');
      await tester.pumpWidget(app(const DeletedProfessionsPage()));
      await tester.pumpAndSettle();
      final button = tester.widget<TactileButton>(
        find.widgetWithText(TactileButton, 'Delete Permanently'),
      );
      expect(button.onPressed, isNull);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(TactileButton, 'Restore'),
          matching: find.text('Restore'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await SettingsStore.instance.loadActiveProfessions(), [
        'Electrician',
      ]);
      expect((await EntryRepository().loadAll()).length, 2);
    },
  );

  testWidgets(
    'search excludes deleted records and includes them after restoration on reopen',
    (tester) async {
      await tester.pumpWidget(app(const GlobalSearchPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Course 2');
      await tester.pumpAndSettle();
      expect(find.text('Electrician'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await SettingsStore.instance.restoreRecord(2);
      await tester.pumpWidget(app(const GlobalSearchPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Course 2');
      await tester.pumpAndSettle();
      expect(find.text('Electrician'), findsOneWidget);
    },
  );
}
