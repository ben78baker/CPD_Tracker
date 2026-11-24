import 'dart:async';
import 'dart:convert';

import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress_panel.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/widgets/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase6_rehearsal_app.dart';
import 'phase7_rehearsal_pages.dart';

const _nursing = RecordingCollection(
  'nmc-test',
  'Nursing · community practice',
  1,
);

class _NursingProgressRepository implements SqliteRecordingRepository {
  int layoutReads = 0;
  Completer<void>? nextRead;
  final records = <RecordingRecord>[];

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteRecordingRepository) run) =>
      run(this);

  @override
  Future<List<RecordingCollection>> loadCollections() async => [_nursing];

  @override
  Future<RecordingCollection?> loadCollection(String id) async =>
      id == _nursing.id ? _nursing : null;

  @override
  Future<List<LayoutRevision>> loadLayouts(String collectionId) async {
    layoutReads++;
    await nextRead?.future;
    return [
      LayoutRevision(
        collectionId: collectionId,
        version: 1,
        fields: nursingBundle.recipe.fields,
        templateId: nursingBundle.recipe.id,
        templateVersion: nursingBundle.recipe.version,
      ),
    ];
  }

  @override
  Future<Map<String, String>> loadHostState(String namespace) async =>
      namespace == SchemePeriodStore.namespace(_nursing.id)
      ? {
          'selected': rehearsalPeriod.id,
          'period:${rehearsalPeriod.id}': jsonEncode(rehearsalPeriod.toJson()),
        }
      : {};

  @override
  Future<List<RecordingRecord>> loadRecords(
    String id, {
    bool includeDeleted = false,
  }) async => records;

  @override
  Future<RecordingRecord?> loadRecord(String id) async =>
      records.where((record) => record.id == id).firstOrNull;

  @override
  Future<RecordingAttachment?> loadAttachment(String id) async =>
      id == 'present'
      ? RecordingAttachment(
          id: id,
          kind: AttachmentKind.link,
          locator: 'https://example.test/evidence',
          name: 'Evidence',
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'scrolling past a loaded scheme card keeps the next tile in place',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 750));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _NursingProgressRepository();
      final store = ProfessionCreationStore(
        repository,
        templates: const {},
        reportRules: const {},
      );
      final cardKey = ValueKey(_nursing.id);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HomeProfessionList(
              itemCount: 20,
              itemBuilder: (context, index) => index == 4
                  ? RehearsalProfessionCard(
                      key: cardKey,
                      store: store,
                      profession: _nursing,
                      onAdd: () {},
                      onScan: () {},
                      onView: () {},
                      onSearch: () {},
                      onRename: () {},
                      onDelete: () {},
                      onRefresh: () {},
                      onOpenReviewRecord: (_) {},
                    )
                  : SizedBox(height: 200, child: Text('Neighbour $index')),
            ),
          ),
        ),
      );
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final card = find.byKey(cardKey, skipOffstage: false);
      final neighbour = find.text('Neighbour 5');

      scroll.position.jumpTo(835);
      await tester.pumpAndSettle();
      final loadedHeight = tester.getSize(card).height;
      expect(find.textContaining('Activities to review'), findsNothing);
      expect(repository.layoutReads, 1);
      repository.nextRead = Completer<void>();

      scroll.position.jumpTo(2520);
      await tester.pumpAndSettle();
      expect(neighbour, findsNothing);
      scroll.position.jumpTo(1225);
      await tester.pump();
      final neighbourY = tester.getTopLeft(neighbour).dy;
      expect(tester.getSize(card).height, loadedHeight);
      expect(repository.layoutReads, 1);

      repository.nextRead!.complete();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(neighbour).dy, neighbourY);
    },
  );

  testWidgets('review button lists reasons and opens the flagged record', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = _NursingProgressRepository();
    for (var index = 0; index <= 10; index++) {
      repo.records.add(
        RecordingRecord(
          id: 'record-$index',
          collectionId: _nursing.id,
          layoutVersion: 1,
          version: 1,
          deleted: false,
          values: {
            ...nursingBundle.examples.first.values,
            nursingBundle.inputs[ActivityInput.title]!: index == 0
                ? 'Complete activity'
                : 'Flagged activity $index',
            nursingBundle.inputs[ActivityInput.evidence]!: [
              index == 0 ? 'present' : 'unavailable',
            ],
            if (index == 9)
              nursingBundle.inputs[ActivityInput.participatory]!: 125,
          },
        ),
      );
    }
    final store = phase6Store(repo);
    await tester.pumpWidget(Phase6App(open: () async => store, phase7: true));
    await tester.pumpAndSettle();
    final review = find.text('Activities to review · 10');
    await tester.scrollUntilVisible(review, 180);
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Evidence unavailable')),
      findsWidgets,
    );
    expect(find.text('Complete activity'), findsNothing);

    final lastFlag = find.text('Flagged activity 9');
    final dialogList = find.descendant(
      of: dialog,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(lastFlag, 150, scrollable: dialogList);
    await tester.ensureVisible(lastFlag);
    await tester.pumpAndSettle();
    expect(find.text('Invalid or incompatible values'), findsOneWidget);
    await tester.tap(lastFlag);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.text('View Record'), findsOneWidget);
    final advisory = find.byType(SchemeRecordAdvisory);
    expect(advisory, findsOneWidget);
    final reason = find.descendant(
      of: advisory,
      matching: find.text('Evidence unavailable'),
    );
    final context = tester.element(advisory);
    final red = Theme.of(context).colorScheme.error;
    expect(tester.widget<Text>(reason).style?.color, red);
    final box = tester.widget<Container>(
      find.descendant(of: advisory, matching: find.byType(Container)),
    );
    expect(
      ((box.decoration as BoxDecoration).border! as Border).top.color,
      red,
    );
    await tester.scrollUntilVisible(find.text('Flagged activity 9'), 130);
    expect(find.text('Flagged activity 9'), findsOneWidget);
  });
}
