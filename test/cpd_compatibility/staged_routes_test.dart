import 'package:cpd_tracker/add_entry_page.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_data_store.dart';
import 'package:cpd_tracker/deleted_records_page.dart';
import 'package:cpd_tracker/home_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:cpd_tracker/widgets/record_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/profession_recovery_test.dart' show record;

void main() {
  testWidgets(
    'staged routes use the injected store while preferences remain separate',
    (tester) async {
      final data = _StagedData();
      SharedPreferences.setMockInitialValues({
        'professions': ['Legacy profession'],
        'entries_json_list': [record(1, 'Legacy profession').toJson()],
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(dataStore: data),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic profession'), findsOneWidget);
      expect(find.text('Legacy profession'), findsNothing);
      tester.widget<ProfessionCard>(find.byType(ProfessionCard)).onView();
      await tester.pumpAndSettle();
      expect(find.text('Course 2'), findsOneWidget);
      expect(find.text('Course 1'), findsNothing);
      tester.widget<RecordCard>(find.byType(RecordCard)).onEdit!();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AddEntryPage>(find.byType(AddEntryPage)).recordStore,
        same(data),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('professions'), ['Legacy profession']);
      expect(prefs.getStringList('entries_json_list'), [
        record(1, 'Legacy profession').toJson(),
      ]);
    },
  );

  testWidgets('deleted record recovery calls the injected profession store', (
    tester,
  ) async {
    final data = _StagedData();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DeletedRecordsPage(dataStore: data),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('restore-record-3')),
        matching: find.text('Restore'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(data.restored, 3);
    expect(find.text('No deleted records'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}

class _StagedData extends CpdDataStore {
  int? restored;

  @override
  Future<List<CpdEntry>> loadAll() async => [
    record(2, 'Synthetic profession'),
    record(3, 'Synthetic profession', deleted: restored != 3),
  ];

  @override
  Future<List<String>> loadActiveProfessions() async => [
    'Synthetic profession',
  ];

  @override
  Future<List<String>> loadDeletedProfessions() async => [];

  @override
  Future<(int, String)?> getTarget(String profession) async => null;

  @override
  Future<void> restoreRecord(int id, {bool recoverProfession = false}) async {
    restored = id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
