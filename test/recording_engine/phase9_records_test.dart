import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_records_source.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase6_rehearsal_app.dart';
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
  String details = 'Synthetic notes',
}) => CpdRecordItem(
  id: '${profession.id}-$day',
  professionId: profession.id,
  entry: CpdEntry(
    id: day,
    profession: profession.label,
    date: DateTime(2026, 1, day),
    title: title,
    details: details,
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
  final link = RecordingAttachment(
    id: 'evidence-link',
    kind: AttachmentKind.link,
    locator: 'https://example.test/certificate',
    name: 'Certificate website',
  );

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteRecordingRepository) run) =>
      run(this);

  @override
  Future<List<RecordingCollection>> loadCollections() async => [
    RecordingCollection(standard.id, standard.label, 1),
  ];

  @override
  Future<RecordingCollection?> loadCollection(String id) async =>
      id == standard.id
      ? RecordingCollection(standard.id, standard.label, 1)
      : null;

  @override
  Future<List<LayoutRevision>> loadLayouts(String id) async => [layout];

  @override
  Future<List<RecordingRecord>> loadRecords(
    String id, {
    bool includeDeleted = false,
  }) async => rows.values
      .where(
        (record) =>
            record.collectionId == id && (includeDeleted || !record.deleted),
      )
      .toList();

  @override
  Future<RecordingRecord?> loadRecord(String id) async => rows[id];

  @override
  Future<void> setRecordDeleted(
    String id,
    bool deleted, {
    required int expectedVersion,
  }) async {
    final record = rows[id]!;
    if (record.version != expectedVersion) throw StateError('Stale edit');
    if (record.deleted == deleted) return;
    rows[id] = RecordingRecord(
      id: record.id,
      collectionId: record.collectionId,
      layoutVersion: record.layoutVersion,
      version: record.version + 1,
      deleted: deleted,
      values: record.values,
    );
  }

  @override
  Future<Map<String, String>> loadHostState(String namespace) async =>
      hostState[namespace] ?? {};

  @override
  Future<RecordingAttachment?> loadAttachment(String id) async =>
      id == asset.id ? asset : (id == link.id ? link : null);

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
                onOpenReviewRecord: (_) {},
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
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const longDetails =
        'Started the activity.\nReflected on the result.\nPlanned a follow-up.';
    final source = FixtureSource([
      row(standard, 1, 'First activity', details: 'Brief'),
      row(standard, 2, 'Latest activity', details: longDetails),
    ]);
    final opened = <(String, bool)>[];
    await tester.pumpWidget(
      app(
        CpdRecordsPage(
          profession: standard.label,
          professionId: standard.id,
          source: source,
          onOpenRecord: (item, {required view}) async =>
              opened.add((item.id, view)),
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
    final description = find.text(longDetails);
    expect(tester.widget<Text>(description).maxLines, 2);
    expect(tester.widget<Text>(description).overflow, TextOverflow.ellipsis);
    expect(
      tester.renderObject<RenderParagraph>(description).didExceedMaxLines,
      isTrue,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Brief'))
          .didExceedMaxLines,
      isFalse,
    );
    for (final part in [
      find.text('Latest activity'),
      find.text('02/01/2026'),
      description,
    ]) {
      await tester.tap(part);
      await tester.pumpAndSettle();
    }
    expect(opened, List.filled(3, ('standard-id-2', true)));
    final menu = find.descendant(
      of: find.byKey(const ValueKey('standard-id-2')),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(opened, hasLength(3));
    await tester.tap(find.text('View Record'));
    await tester.pumpAndSettle();
    expect(opened.last, ('standard-id-2', true));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(opened, hasLength(4));
    await tester.tap(find.text('Edit Record').last);
    await tester.pumpAndSettle();
    expect(opened.last, ('standard-id-2', false));
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

  testWidgets(
    'view opens evidence and refreshes after the shared editor saves',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 1050));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = Directory.systemTemp.createTempSync('cpd-view-record-');
      addTearDown(() => root.deleteSync(recursive: true));
      final repository = EvidenceRepository();
      final originals = ManagedAttachmentFiles(root);
      final file = File('${root.path}/${repository.asset.locator}')
        ..writeAsStringSync('Original bytes');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const title = 'Workshop with evidence';
      const details = 'First line\nSecond line\nThird line\nLast line';
      const newDetails = 'Updated notes\nEvidence still intact';
      final bindings = cpdFieldBindings(repository.layout.fields);
      final evidenceId = bindings['cpd.evidence']!;
      final item = row(standard, 1, title, details: details);
      repository.rows[item.id] = RecordingRecord(
        id: item.id,
        collectionId: item.professionId,
        layoutVersion: 1,
        version: 1,
        deleted: false,
        values: {
          bindings['cpd.title']!: title,
          bindings['cpd.details']!: details,
          bindings['cpd.activityDate']!: '2026-01-01',
          bindings['cpd.creditedDuration']!: 75,
          evidenceId: [repository.asset.id, repository.link.id],
        },
      );
      final store = ProfessionCreationStore(
        repository,
        templates: const {},
        reportRules: const {},
        evaluationLedger: const TemplateEvaluationLedger(),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => CpdRecordsPage(
              profession: standard.label,
              professionId: standard.id,
              source: FixtureSource([item, row(standard, 2, 'Other activity')]),
              initialSearchQuery: 'Workshop',
              onOpenRecord: (item, {required view}) => RehearsalRecordPage.open(
                context,
                store: store,
                professionId: item.professionId,
                recordId: item.id,
                view: view,
                originals: originals,
                onEditFields: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Other activity'), findsNothing);
      await tester.tap(find.text(details));
      await tester.pumpAndSettle();
      expect(find.text('View Record'), findsOneWidget);
      expect(tester.widget<Text>(find.text(details)).maxLines, isNull);
      expect(find.byType(InputChip), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      final attachment = find.widgetWithText(ActionChip, repository.asset.name);
      expect(attachment, findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, repository.link.name));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'launch');
      expect(calls.single.arguments['url'], repository.link.locator);

      await tester.tap(find.widgetWithText(FilledButton, 'Edit Record'));
      await tester.pumpAndSettle();
      final evidence = find.widgetWithText(InputChip, repository.asset.name);
      expect(tester.widget<InputChip>(evidence).onDeleted, isNotNull);
      expect(find.byType(OutlinedButton), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, details),
        newDetails,
      );
      await tester.binding.setSurfaceSize(const Size(390, 600));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      final list = find.byType(ListView);
      await tester.dragFrom(
        tester.getTopLeft(list) + const Offset(8, 240),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Edit Record'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(390, 1050));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('View Record'), findsOneWidget);
      expect(find.text(newDetails), findsOneWidget);
      expect(find.text(details), findsNothing);
      expect(attachment, findsOneWidget);
      expect(repository.rows[item.id]!.values[evidenceId], [
        repository.asset.id,
        repository.link.id,
      ]);
      expect(file.readAsStringSync(), 'Original bytes');

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Edit fields'), findsOneWidget);
      expect(find.text('Delete Record'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(PopupMenuItem<String>, 'Edit Record'),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, newDetails), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Edit Record'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Workshop'), findsOneWidget);
      expect(find.text('Other activity'), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Record'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, newDetails), findsOneWidget);
      expect(find.text('View Record'), findsNothing);
    },
  );

  testWidgets(
    'View Record confirms soft deletion and returns to filtered records',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const recordId = 'delete-from-view';
      const title = 'Workshop to delete';
      final repository = EvidenceRepository();
      final fields = cpdFieldBindings(repository.layout.fields);
      final record = RecordingRecord(
        id: recordId,
        collectionId: standard.id,
        layoutVersion: 1,
        version: 1,
        deleted: false,
        values: {
          fields['cpd.title']!: title,
          fields['cpd.activityDate']!: '2026-01-01',
          fields['cpd.evidence']!: [repository.link.id],
        },
      );
      repository.rows[recordId] = record;
      final originals = ManagedAttachmentFiles(Directory.systemTemp);
      final source = SqliteCpdRecordsSource(
        repository,
        originals,
        preferences: () async => {},
        setReportLanguage: (_) async {},
      );
      final store = ProfessionCreationStore(
        repository,
        templates: const {},
        reportRules: const {},
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => CpdRecordsPage(
              profession: standard.label,
              professionId: standard.id,
              source: source,
              initialSearchQuery: 'Workshop',
              onOpenRecord: (item, {required view}) => RehearsalRecordPage.open(
                context,
                store: store,
                professionId: item.professionId,
                recordId: item.id,
                view: view,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      Future<void> requestDelete() async {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Record'));
        await tester.pumpAndSettle();
        expect(find.text('Delete record?'), findsOneWidget);
      }

      await requestDelete();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('View Record'), findsOneWidget);
      expect(repository.rows[recordId], same(record));

      await requestDelete();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('View Record'), findsNothing);
      expect(find.text(title), findsNothing);
      expect(find.text('Workshop'), findsOneWidget);
      final deleted = (await source.records(deleted: true)).single;
      expect(deleted.id, record.id);
      expect(repository.rows[recordId]!.values, record.values);
      expect(deleted.evidence.single.id, repository.link.id);
      await source.setDeleted(deleted, false);
      expect((await source.records()).single.id, record.id);
    },
  );

  testWidgets(
    'scrolling record results dismisses the keyboard and keeps the query',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          CpdRecordsPage(
            profession: standard.label,
            professionId: standard.id,
            source: FixtureSource([
              for (var day = 1; day <= 10; day++)
                row(standard, day, 'Workshop $day'),
              row(standard, 11, 'Other activity'),
            ]),
            startInSearchMode: true,
            onOpenRecord: (_, {required view}) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.enterText(search, 'Workshop');
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(search).controller!.text, 'Workshop');
      expect(find.text('Other activity'), findsNothing);
    },
  );

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
