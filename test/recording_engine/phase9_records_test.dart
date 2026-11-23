import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_records_source.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_records_page.dart';
import 'package:cpd_tracker/deleted_records_page.dart';
import 'package:cpd_tracker/global_search_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/widgets/record_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase7_rehearsal_pages.dart';

const standard = (id: 'standard-id', label: 'Standard', deleted: false);
const template = (id: 'nmc-id', label: 'Nursing', deleted: false);
const archived = (id: 'archived-id', label: 'Custom', deleted: true);

CpdRecordItem row(
  CpdProfessionItem profession,
  int day,
  String title, {
  bool deleted = false,
  List<String> terms = const [],
}) => CpdRecordItem(
  id: '${profession.id}-$day',
  professionId: profession.id,
  entry: CpdEntry(
    id: day,
    profession: profession.label,
    date: DateTime(2026, 1, day),
    title: title,
    details: 'Synthetic notes',
    hours: 1,
    minutes: 15,
    attachments: [],
    deleted: deleted,
  ),
  additionalSearchText: terms,
);

class FixtureSource implements CpdRecordsSource {
  FixtureSource(this.rows);

  final List<CpdRecordItem> rows;
  (String, bool, bool)? lastDelete;
  ReportLanguage language = ReportLanguage.app;

  @override
  Future<List<CpdProfessionItem>> professions() async => [
    standard,
    template,
    archived,
  ];

  @override
  Future<List<CpdRecordItem>> records({
    String? professionId,
    bool deleted = false,
  }) async => rows
      .where(
        (item) =>
            (professionId == null || professionId == item.professionId) &&
            item.entry.deleted == deleted,
      )
      .toList();

  @override
  Future<void> setDeleted(
    CpdRecordItem item,
    bool deleted, {
    bool recoverProfession = false,
  }) async {
    lastDelete = (item.id, deleted, recoverProfession);
    rows.remove(item);
  }

  @override
  Future<Map<String, String>> preferences() async => {
    'reportLocale': language.tag,
  };

  @override
  Future<void> setReportLanguage(ReportLanguage value) async =>
      language = value;

  @override
  Future<void> unlinkEvidence(
    String recordId,
    int version,
    CpdEvidenceItem evidence,
  ) async {}
}

class EvidenceRepository implements SqliteRecordingRepository {
  final layout = LayoutRevision(
    collectionId: standard.id,
    version: 1,
    fields: cpdStandardFields(standard.id),
  );
  final rows = <String, RecordingRecord>{};
  final hostState = <String, Map<String, String>>{};
  final asset = RecordingAttachment(
    id: 'shared-asset',
    kind: AttachmentKind.managed,
    locator: 'shared.pdf',
    name: 'Original certificate.pdf',
  );

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteRecordingRepository) run) =>
      run(this);

  @override
  Future<List<RecordingCollection>> loadCollections() async => [
    RecordingCollection(standard.id, standard.label, 1),
  ];

  @override
  Future<List<LayoutRevision>> loadLayouts(String id) async => [layout];

  @override
  Future<List<RecordingRecord>> loadRecords(
    String id, {
    bool includeDeleted = false,
  }) async => rows.values.toList();

  @override
  Future<RecordingRecord?> loadRecord(String id) async => rows[id];

  @override
  Future<Map<String, String>> loadHostState(String namespace) async =>
      hostState[namespace] ?? {};

  @override
  Future<RecordingAttachment?> loadAttachment(String id) async =>
      id == asset.id ? asset : null;

  @override
  Future<RecordingRecord> updateValues(
    String id,
    Map<String, Object?> changes, {
    required int expectedVersion,
    Iterable<RecordingAttachment> newAttachments = const [],
  }) async {
    final original = rows[id]!;
    if (original.version != expectedVersion) throw StateError('Stale edit');
    final values = Map<String, Object>.of(original.values);
    for (final change in changes.entries) {
      if (change.value case final value?) {
        values[change.key] = value;
      } else {
        values.remove(change.key);
      }
    }
    return rows[id] = RecordingRecord(
      id: id,
      collectionId: original.collectionId,
      layoutVersion: original.layoutVersion,
      version: expectedVersion + 1,
      deleted: false,
      values: values,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget page) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: page,
);

void main() {
  testWidgets('standard target cards read migrated credit and refresh', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'week_start': 'saturday'});
    final repository = EvidenceRepository()
      ..hostState['cpd.preferences'] = {
        'targets': '{"standard":{"minutes":120,"cycle":"week"}}',
      };
    final fields = cpdFieldBindings(repository.layout.fields);
    final (saturday, _) = cpdTargetPeriod(
      DateTime.now(),
      'week',
      firstWeekday: DateTime.saturday,
    );
    void addActivity(String id) {
      repository.rows[id] = RecordingRecord(
        id: id,
        collectionId: standard.id,
        layoutVersion: 1,
        version: 1,
        deleted: false,
        values: {
          fields['cpd.activityDate']!: saturday
              .toIso8601String()
              .split('T')
              .first,
          fields['cpd.creditedDuration']!: 30,
        },
      );
    }

    addActivity('first');
    final store = ProfessionCreationStore(
      repository,
      templates: const {},
      reportRules: const {},
    );
    late StateSetter refresh;
    var token = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return RehearsalProfessionCard(
                store: store,
                profession: RecordingCollection(standard.id, standard.label, 1),
                onAdd: () {},
                onScan: () {},
                onView: () {},
                onSearch: () {},
                onRename: () {},
                onDelete: () {},
                onRefresh: () {},
                refreshToken: token,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strings = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(strings.weekStartsOnDay(strings.saturday)),
      findsOneWidget,
    );
    expect(
      find.text(strings.timeRemaining(1, 30, strings.thisWeek)),
      findsOneWidget,
    );
    addActivity('second');
    refresh(() => token++);
    await tester.pumpAndSettle();
    expect(
      find.text(strings.timeRemaining(1, 0, strings.thisWeek)),
      findsOneWidget,
    );
  });

  test(
    'unlink uses the exact evidence occurrence and retains a shared original',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cpd-shared-evidence-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = await File(
        '${root.path}/shared.pdf',
      ).writeAsString('fixture');
      final repository = EvidenceRepository();
      final fields = cpdFieldBindings(repository.layout.fields);
      final fieldId = fields['cpd.evidence']!;
      for (final (id, evidence) in [
        ('record-a', ['shared-asset', 'shared-asset']),
        ('record-b', ['shared-asset']),
      ]) {
        repository.rows[id] = RecordingRecord(
          id: id,
          collectionId: standard.id,
          layoutVersion: 1,
          version: 1,
          deleted: false,
          values: {
            fields['cpd.activityDate']!: '2026-01-01',
            fieldId: evidence,
          },
        );
      }
      final source = SqliteCpdRecordsSource(
        repository,
        ManagedAttachmentFiles(root),
        preferences: () async => {},
        setReportLanguage: (_) async {},
      );
      final before = (await source.records(professionId: standard.id)).first;
      expect(before.matches('original certificate.pdf'), isTrue);
      final path = await file.resolveSymbolicLinks();
      expect(before.evidence.map((asset) => asset.target), [path, path]);
      await source.unlinkEvidence(
        before.id,
        before.version,
        before.evidence.last,
      );
      expect(repository.rows['record-a']!.values[fieldId], ['shared-asset']);
      expect(repository.rows['record-b']!.values[fieldId], ['shared-asset']);
      expect(await file.readAsString(), 'fixture');
      await expectLater(
        source.unlinkEvidence(before.id, before.version, before.evidence.first),
        throwsStateError,
      );
      expect(repository.rows['record-a']!.values[fieldId], ['shared-asset']);
    },
  );

  testWidgets('shared cards put real dates first and use stable action IDs', (
    tester,
  ) async {
    final source = FixtureSource([
      row(standard, 1, 'First activity'),
      row(standard, 2, 'Latest activity'),
    ]);
    (String, bool)? opened;
    await tester.pumpWidget(
      app(
        CpdRecordsPage(
          profession: standard.label,
          professionId: standard.id,
          source: source,
          onOpenRecord: (item, {required view}) async =>
              opened = (item.id, view),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RecordCard), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Latest activity')).dy,
      lessThan(tester.getTopLeft(find.text('First activity')).dy),
    );
    expect(find.text('02/01/2026'), findsOneWidget);
    expect(find.text('1 hour 15 minutes'), findsWidgets);
    await tester.tap(find.text('Latest activity'));
    await tester.pumpAndSettle();
    expect(opened, ('standard-id-2', true));
    final menu = find.descendant(
      of: find.byKey(const ValueKey('standard-id-2')),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(opened, ('standard-id-2', false));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(source.lastDelete, isNull);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(source.lastDelete, ('standard-id-2', true, false));
    expect(find.text('Latest activity'), findsNothing);
  });

  testWidgets('global evidence search opens the right record and profession', (
    tester,
  ) async {
    final source = FixtureSource([
      row(standard, 1, 'Standard workshop', terms: ['SharedEvidence.pdf']),
      row(
        template,
        2,
        'NMC workshop',
        terms: ['SharedEvidence.pdf', 'https://example.test/nmc'],
      ),
    ]);
    String? opened;
    String? filtered;
    await tester.pumpWidget(
      app(
        GlobalSearchPage(
          source: source,
          onOpenRecord: (item) async => opened = item.id,
          onOpenProfession: (profession, query) async =>
              filtered = '${profession.id}:$query',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'EXAMPLE.TEST/NMC');
    await tester.pumpAndSettle();
    expect(find.text('Standard workshop'), findsNothing);
    await tester.tap(find.text('NMC workshop'));
    await tester.pumpAndSettle();
    expect(opened, 'nmc-id-2');
    await tester.tap(find.text('Open filtered records'));
    await tester.pumpAndSettle();
    expect(filtered, 'nmc-id:EXAMPLE.TEST/NMC');
  });

  testWidgets('confirmed restore uses the archived profession ID', (
    tester,
  ) async {
    final source = FixtureSource([
      row(archived, 2, 'Archived record', deleted: true),
    ]);
    await tester.pumpWidget(app(DeletedRecordsPage(source: source)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(source.lastDelete, isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(source.lastDelete, ('archived-id-2', false, true));
  });

  testWidgets('additional report uses query and inclusive date selection', (
    tester,
  ) async {
    final source = FixtureSource([
      row(template, 1, 'Workshop first'),
      row(template, 2, 'Other activity'),
      row(template, 3, 'Workshop last'),
    ]);
    List<String>? exported;
    await tester.pumpWidget(
      app(
        CpdRecordsPage(
          profession: template.label,
          professionId: template.id,
          source: source,
          startInSearchMode: true,
          initialSearchQuery: 'Workshop',
          onOpenRecord: (_, {required view}) async {},
          additionalFormats: const {'field_csv': 'Field values export'},
          onAdditionalExport: (_, records, _) async {
            exported = records.map((item) => item.id).toList();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Other activity'), findsNothing);
    expect(find.text('Workshop'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    await tester.tap(find.text('To').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.1;
    await tester.pumpAndSettle();
    expect(find.text('02/01/2026'), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Field values export'));
    await tester.tap(find.text('Field values export'));
    await tester.pumpAndSettle();
    expect(exported, ['nmc-id-1']);
  });
}
