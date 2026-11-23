import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_duration.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejectsDuration(Future<void> Function() save) async {
  try {
    await save();
  } on ArgumentError catch (error) {
    if (error.name == 'credited duration') return;
    rethrow;
  }
  throw StateError('An out-of-range duration was accepted.');
}

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Use a disposable debug app.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Duration validation'))));
  final root = await Directory.systemTemp.createTemp(
    'cpd_duration_validation_',
  );
  final repository = await SqliteRecordingRepository.open(
    RecordingWorkspace(root).databasePath,
  );
  try {
    await verifyDurationsAndTargets(repository, root);
    debugPrintSynchronously('CPD_DURATION_TARGETS_PASS');
  } on Object catch (error, trace) {
    debugPrintSynchronously('CPD_DURATION_TARGETS_FAIL $error\n$trace');
    rethrow;
  } finally {
    await repository.close();
    await root.delete(recursive: true);
  }
}

Future<void> verifyDurationsAndTargets(
  SqliteRecordingRepository repository,
  Directory root,
) async {
  const profession = 'Synthetic engineering';
  check(
    await SqliteCpdStore.collectionTarget(
          repository,
          const RecordingCollection('new', 'New profession', 1),
        ) ==
        null,
    'A fresh test app should not require migrated target metadata.',
  );
  SharedPreferences.setMockInitialValues({
    'professions': [profession],
    'targets_v1':
        '{"synthetic engineering":{"minutes":840,"cycle":"week","keep":true}}',
    'week_start': 'saturday',
    'entries_json_list': [
      for (final (index, minutes) in [0, cpdMaxCreditedMinutes, 60325].indexed)
        jsonEncode({
          'id': index + 1,
          'profession': profession,
          'title': 'Original ${index + 1}',
          'date': ['2026-11-22', '2026-11-21', '2026-11-20'][index],
          'hours': minutes ~/ 60,
          'minutes': minutes % 60,
        }),
    ],
  });
  final raw = await readCpdLegacyPreferences(
    await SharedPreferences.getInstance(),
  );
  final migration = SyntheticCpdMigration(repository, root);
  await migration.stage(raw);
  await migration.verify(raw);
  final legacySurface = await SqliteCpdStore.openVerified(
    repository,
    sourceId: SyntheticCpdMigration.sourceIdentity(raw),
    documents: root,
  );
  await legacySurface.verifyLegacyProjection(raw);
  final group = (await repository.loadCollections()).single;
  final host = ProfessionCreationStore(
    repository,
    templates: const {},
    reportRules: const {},
  );
  final fields = cpdFieldBindings(
    (await repository.loadLayouts(group.id)).single.fields,
  );
  final title = fields['cpd.title']!;
  final duration = fields['cpd.creditedDuration']!;
  final date = fields['cpd.activityDate']!;
  final entries = await repository.loadRecords(group.id);
  for (final entry in entries) {
    final saved = await host.editActivity(entry, {
      title: 'Title only',
    }, expectedLayoutVersion: 1);
    check(
      saved.values[duration] == entry.values[duration] &&
          saved.layoutVersion == entry.layoutVersion,
      'A title-only edit changed historical credit or its layout.',
    );
    await rejectsDuration(
      () =>
          host.editActivity(saved, {duration: 60000}, expectedLayoutVersion: 1),
    );
    check(
      (await repository.loadRecord(entry.id))!.version == saved.version,
      'Rejected duration changed the record.',
    );
  }
  await rejectsDuration(
    () => host.createActivity(group.id, {
      date: '2026-11-22',
      title: 'Rejected',
      duration: 60000,
    }, expectedLayoutVersion: 1),
  );
  check(
    (await repository.loadRecords(group.id)).length == 3,
    'Rejected duration created a record.',
  );
  final weekStart = await SettingsStore.instance.getWeekStart();
  check(
    weekStart == raw['week_start'] && weekStart == 'saturday',
    'The selected legacy preference changed.',
  );
  final (start, end) = cpdTargetPeriod(
    DateTime(2026, 11, 23),
    'week',
    firstWeekday: cpdFirstWeekday(weekStart, 0),
  );
  check(
    await legacySurface.sumMinutesForRange(profession, start, end) == 59999,
    'The selected week start changed credited totals.',
  );
  check(
    await SqliteCpdStore.collectionTarget(repository, group) == (840, 'week'),
    'The test card could not read the migrated target.',
  );
  await SqliteCpdStore.setCollectionTarget(repository, group, (900, 'month'));
  check(
    await legacySurface.getTarget('synthetic engineering') == (900, 'month'),
    'Editing a migrated target created a divergent copy.',
  );
  final targetMap =
      jsonDecode(
            (await repository.loadHostState('cpd.preferences'))['targets']!,
          )
          as Map;
  check(
    (targetMap['synthetic engineering'] as Map)['keep'] == true,
    'An unrelated target preference was lost.',
  );
  await SqliteCpdStore.renameCollectionWithTarget(repository, group, 'Renamed');
  final renamed = (await repository.loadCollections()).single;
  check(
    await SqliteCpdStore.collectionTarget(repository, renamed) ==
            (900, 'month') &&
        await SqliteCpdStore.collectionTarget(repository, group) == null,
    'Renaming the profession lost or duplicated its migrated target.',
  );
}
