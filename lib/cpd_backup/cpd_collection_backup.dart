import 'dart:convert';

import '../cpd_compatibility/cpd_data_store.dart';
import '../cpd_creation/creation_policy.dart';
import '../cpd_creation/historical_bundles.dart';
import '../cpd_creation/profession_creation_store.dart';
import '../cpd_creation/scheme_period_store.dart';
import '../cpd_creation/scheme_progress.dart';
import '../cpd_creation/template_bundle.dart';
import '../recording_engine/models.dart';
import '../recording_engine_storage/portable_archive.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';

const cpdCollectionTargets = 'cpd.phase7.standard-targets';

SqliteCollectionBackup cpdCollectionBackup(AvailableStorage available) =>
    SqliteCollectionBackup(
      available: available,
      projectSettings: _settings,
      verifyHost: const HistoricalCpdBundles().verify,
    );

Future<List<CollectionSetting>> _settings(
  SqliteRecordingRepository source,
  RecordingCollection profession,
  String destination,
  List<TemplateVersion> templates,
) async {
  final result = <CollectionSetting>[];
  void retain(String namespace, String key, String value) =>
      result.add((namespace: namespace, key: key, value: value));
  final reports = await source.loadHostState(
    ProfessionCreationStore.reportsNamespace,
  );
  final layouts = await source.loadLayouts(profession.id);
  final fieldIds = {
    for (final layout in layouts) ...layout.fields.map((f) => f.id),
  };
  for (final layout in layouts) {
    if (reports['${profession.id}:${layout.version}'] case final entry?) {
      final report = ReportSelection.fromJson(jsonDecode(entry) as List);
      if (!fieldIds.containsAll(report.excluded)) {
        throw const BackupException(
          BackupProblem.integrity,
          'Unknown report field.',
        );
      }
      retain(
        ProfessionCreationStore.reportsNamespace,
        '$destination:${layout.version}',
        entry,
      );
    }
  }
  final oldPeriods = SchemePeriodStore.namespace(profession.id);
  final newPeriods = SchemePeriodStore.namespace(destination);
  final periods = await source.loadHostState(oldPeriods);
  for (final entry in periods.entries) {
    if (entry.key == 'selected') {
      retain(newPeriods, entry.key, entry.value);
    } else if (entry.key.startsWith('period:')) {
      final period = SchemePeriod.fromJson(
        jsonDecode(entry.value) as Map<String, dynamic>,
      );
      if (entry.key != 'period:${period.id}') {
        throw const BackupException(
          BackupProblem.integrity,
          'Invalid reporting period identity.',
        );
      }
      retain(newPeriods, entry.key, entry.value);
    }
  }
  final pins = {for (final recipe in templates) (recipe.id, recipe.version)};
  for (final entry in (await source.loadHostState(
    HistoricalCpdBundles.namespace,
  )).entries) {
    final bundle = ProfessionTemplateBundle.decode(entry.value);
    if (pins.contains((bundle.recipe.id, bundle.recipe.version))) {
      retain(HistoricalCpdBundles.namespace, entry.key, entry.value);
    }
  }
  var target = (await source.loadHostState(
    cpdCollectionTargets,
  ))[profession.id];
  if (target == null) {
    final raw = (await source.loadHostState('cpd.preferences'))['targets'];
    if (raw != null) {
      final key = cpdProfessionKey(profession.label);
      final matches = (jsonDecode(raw) as Map).entries
          .where((entry) => cpdProfessionKey(entry.key as String) == key)
          .toList();
      if (matches.length > 1) {
        throw const BackupException(
          BackupProblem.integrity,
          'Conflicting targets.',
        );
      }
      final value = matches.firstOrNull?.value;
      if (value is Map) target = '${value['minutes']}:${value['cycle']}';
    }
  }
  if (target != null) {
    final parts = target.split(':');
    if (parts.length != 2 ||
        (int.tryParse(parts.first) ?? -1) < 0 ||
        !cpdTargetCycles.contains(parts.last)) {
      throw const BackupException(BackupProblem.integrity, 'Invalid target.');
    }
    retain(cpdCollectionTargets, destination, target);
  }
  return result;
}
