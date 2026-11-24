import 'dart:async';
import 'dart:convert';

import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/widgets/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase7_rehearsal_pages.dart';

const _nursing = RecordingCollection(
  'nmc-test',
  'Nursing · community practice',
  1,
);

class _NursingProgressRepository implements SqliteRecordingRepository {
  int layoutReads = 0;
  Completer<void>? nextRead;

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
  Future<Map<String, String>> loadHostState(String namespace) async => {
    'selected': rehearsalPeriod.id,
    'period:${rehearsalPeriod.id}': jsonEncode(rehearsalPeriod.toJson()),
  };

  @override
  Future<List<RecordingRecord>> loadRecords(
    String id, {
    bool includeDeleted = false,
  }) async => [];

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
}
