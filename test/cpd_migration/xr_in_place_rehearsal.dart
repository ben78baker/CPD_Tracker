import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/main.dart' show MyApp;
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'xr_workflow_probe.dart';

/// Dedicated development build installed over the disposable XR installation.
/// Neither this entry point nor its rehearsal authority is used by main.dart.
Future<void> main() async {
  const sourceId = String.fromEnvironment('CPD_XR_EXPECTED_SOURCE');
  if (kReleaseMode || !Platform.isIOS || sourceId.isEmpty) {
    throw UnsupportedError(
      'Use the authorised iOS development build and sealed source.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Status('Verifying the XR migration'));
  try {
    await _open(sourceId);
  } on Object catch (error) {
    // Console contains no raw source rows, paths or attachment names.
    debugPrintSynchronously('CPD_XR_FAILURE ${error.runtimeType}');
    runApp(const _Status('Migration or verification failed. See CPD_XR logs.'));
  }
}

Future<void> _open(String sourceId) async {
  final time = Stopwatch()..start();
  final support = await getApplicationSupportDirectory();
  final root = await Directory(
    p.join(support.path, 'xr-in-place-migration'),
  ).create(recursive: true);
  final events = File(p.join(root.path, 'events.jsonl'));
  void log(String event, [Map<String, Object?> data = const {}]) {
    final line = jsonEncode({
      'event': event,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'elapsedMs': time.elapsedMilliseconds,
      ...data,
    });
    debugPrintSynchronously('CPD_XR $line');
    events.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  final prefs = await SharedPreferences.getInstance();
  Future<Map<String, Object?>> readLegacy() => readCpdLegacyPreferences(prefs);
  final source = await readLegacy();
  final documents = await getApplicationDocumentsDirectory();
  final command = File(p.join(root.path, 'command'));
  var task = 'open';
  if (await command.exists()) {
    if (await command.length() > 64) {
      throw const FormatException('Invalid XR command length.');
    }
    task = (await command.readAsString()).trim();
    await command.delete();
  }
  if (task == 'interrupt-stage' || task == 'resume-interruption') {
    await _checkInterruptedStaging(
      root,
      documents,
      sourceId,
      readLegacy,
      log,
      pause: task == 'interrupt-stage',
    );
    task = 'open';
  }
  if (!const {
    'open',
    'workflows',
    'restart',
    'recovery',
    'ui',
  }.contains(task)) {
    throw const FormatException('Unknown XR command.');
  }
  final gate = LegacyWriteGate.instance;
  final coordinator = CpdMigrationCoordinator(
    workspace: Directory(p.join(root.path, 'attempt')),
    documents: documents,
    gate: gate,
    readLegacy: readLegacy,
    onCheckpoint: (report) async {
      log('checkpoint', {
        'phase': report.phase.name,
        'requiredBytes': report.requiredBytes,
        'availableBytes': report.availableBytes,
        'issues': report.review.map((issue) => issue.code).toList(),
      });
    },
    onFailure: (error) =>
        log('coordinator_error', {'type': error.runtimeType.toString()}),
  );
  final sourceRows = source['entries_json_list'] as List? ?? [];
  log('launch', {
    'task': task,
    'sourceRecords': sourceRows.length,
    'productionActivation': coordinator.productionActivationEnabled,
  });
  if (coordinator.productionActivationEnabled) {
    throw StateError('Unexpected production activation.');
  }
  const scope = AuthorityScope.rehearsal;
  final before = await coordinator.startup.inspect(
    scope: scope,
    hasLegacyRecords: sourceRows.isNotEmpty,
  );
  log('startup', {
    'authority': before.store.name,
    'reason': before.reason.name,
  });
  final migrated = before.store == StoreAuthority.legacy;
  if (migrated) {
    if (SyntheticCpdMigration.sourceIdentity(source) != sourceId) {
      log('source_mismatch');
      throw StateError(
        'The installed legacy source differs from the Mac baseline.',
      );
    }
    final migration = Stopwatch()..start();
    final outcome = await coordinator.rehearseActivation();
    log('migration_result', {
      'phase': outcome.phase.name,
      'failure': outcome.failure,
      'migrationMs': migration.elapsedMilliseconds,
    });
  }
  final authority = await coordinator.startup.resolveAndGuard(
    gate,
    scope: scope,
    hasLegacyRecords: sourceRows.isNotEmpty,
    allowSharedWritesForRecording: true,
  );
  log('authority', {
    'store': authority.store.name,
    'reason': authority.reason.name,
  });
  final receipt = await coordinator.readReceipt();
  if (authority.store != StoreAuthority.recording ||
      receipt?.sourceId != sourceId ||
      receipt?.rehearsal != true) {
    throw StateError(
      'Could not establish the verified development SQLite authority.',
    );
  }

  final original = (await coordinator.snapshot.readVerifiedSource()).values;
  if (SyntheticCpdMigration.sourceIdentity(original) != sourceId) {
    throw StateError('Frozen source changed.');
  }
  await _verifyDatabase(coordinator.databasePath, log);
  if (task == 'recovery') {
    await _checkRecovery(coordinator, root, log);
  }
  final repository = await SqliteRecordingRepository.open(
    coordinator.databasePath,
    durableWrites: true,
  );
  final store = await SqliteCpdStore.openVerified(
    repository,
    sourceId: sourceId,
    documents: documents,
  );
  if (migrated) {
    await coordinator.snapshot.verifyAgainstSource(source, documents);
    await store.verifyLegacyProjection(original);
    log('initial_parity', {
      'records': (await store.loadAll()).length,
      'deleted': (await store.loadDeleted()).length,
      'activeProfessions': (await store.loadActiveProfessions()).length,
      'deletedProfessions': (await store.loadDeletedProfessions()).length,
      'preferencesMatch': true,
      'evidenceFingerprintsMatch': true,
    });
  }
  if (task == 'workflows' || task == 'restart') {
    try {
      await xrWorkflowProbe(
        store,
        repository,
        root,
        readLegacy,
        original,
        log,
        write: task == 'workflows',
      );
    } on XrProbeFailure catch (error) {
      log('workflow_failed', {'check': error.check});
      rethrow;
    } on Object catch (error) {
      log('workflow_error', {'type': error.runtimeType.toString()});
      rethrow;
    }
    await _verifyDatabase(coordinator.databasePath, log);
  }
  await SettingsStore.instance.prewarm();
  runApp(MyApp(dataStore: store));
  WidgetsBinding.instance.addPostFrameCallback((_) => log('home_first_frame'));
  if (task == 'ui') {
    try {
      await xrScreenProbe(store, log);
    } on XrProbeFailure catch (error) {
      log('ui_failed', {'check': error.check});
      rethrow;
    } on Object catch (error) {
      log('ui_error', {'type': error.runtimeType.toString()});
      rethrow;
    }
  }
}

Future<void> _checkInterruptedStaging(
  Directory root,
  Directory documents,
  String sourceId,
  Future<Map<String, Object?>> Function() readLegacy,
  XrLog log, {
  required bool pause,
}) async {
  final source = await readLegacy();
  if (SyntheticCpdMigration.sourceIdentity(source) != sourceId) {
    throw StateError(
      'The interruption probe source differs from the baseline.',
    );
  }
  final workspace = Directory(p.join(root.path, 'interruption-attempt'));
  final coordinator = CpdMigrationCoordinator(
    workspace: workspace,
    documents: documents,
    gate: LegacyWriteGate(),
    readLegacy: readLegacy,
    onCheckpoint: (report) async {
      if (pause && report.phase.name == 'staging') {
        log('interruption_ready', {'phase': report.phase.name});
        await Future<void>.delayed(const Duration(seconds: 120));
        throw StateError('Interruption probe was not terminated.');
      }
    },
  );
  const scope = AuthorityScope.rehearsal;
  final before = await coordinator.startup.inspect(
    scope: scope,
    hasLegacyRecords: true,
  );
  log('interruption_startup', {
    'authority': before.store.name,
    'reason': before.reason.name,
    'pause': pause,
  });
  if (!pause &&
      (before.store != StoreAuthority.legacy ||
          before.reason.name != 'interruptedStaging')) {
    throw StateError(
      'Interrupted staging did not safely retain legacy authority.',
    );
  }
  final result = await coordinator.rehearseActivation();
  final after = await coordinator.startup.inspect(
    scope: scope,
    hasLegacyRecords: true,
  );
  log('interruption_result', {
    'outcome': result.phase.name,
    'authority': after.store.name,
  });
  if (pause || after.store != StoreAuthority.recording) {
    throw StateError(
      'Interruption probe did not resume to verified authority.',
    );
  }
  await workspace.delete(recursive: true);
}

Future<void> _verifyDatabase(String path, XrLog log) async {
  final read = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final integrity = (await read.rawQuery(
      'PRAGMA integrity_check',
    )).single.values.single;
    final foreignKeys = (await read.rawQuery(
      'PRAGMA foreign_key_check',
    )).length;
    log('database', {
      'bytes': await File(path).length(),
      'schema': (await read.rawQuery(
        'PRAGMA user_version',
      )).single.values.single,
      'integrity': integrity,
      'foreignKeyViolations': foreignKeys,
    });
    if (integrity != 'ok' || foreignKeys != 0) {
      throw StateError('Database integrity check failed.');
    }
  } finally {
    await read.close();
  }
}

Future<void> _checkRecovery(
  CpdMigrationCoordinator coordinator,
  Directory root,
  XrLog log,
) async {
  final scratch = await root.createTemp('fault-probe-');
  try {
    final authority = CpdMigrationCoordinator(
      workspace: scratch,
      documents: coordinator.documents,
      readLegacy: coordinator.readLegacy,
      gate: LegacyWriteGate(),
    );
    await coordinator.startup.fence.copy(authority.startup.fence.path);
    try {
      final missing = await authority.startup.inspect(
        scope: AuthorityScope.rehearsal,
        hasLegacyRecords: true,
      );
      if (missing.store != StoreAuthority.recovery) {
        throw StateError('Fence allowed legacy fallback.');
      }
      await File(authority.databasePath).writeAsString('synthetic corruption');
      final corrupt = await authority.startup.inspect(
        scope: AuthorityScope.rehearsal,
        hasLegacyRecords: true,
      );
      if (corrupt.store != StoreAuthority.recovery) {
        throw StateError('Corrupt database allowed legacy fallback.');
      }
      log('recovery_copy_pass', {
        'missing': missing.reason.name,
        'corrupt': corrupt.reason.name,
      });
    } finally {
      await authority.startup.fence.delete();
    }
  } finally {
    await scratch.delete(recursive: true);
  }
}

class _Status extends StatelessWidget {
  const _Status(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(message))),
  );
}
