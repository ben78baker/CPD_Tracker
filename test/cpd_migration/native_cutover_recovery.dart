import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'native_rehearsal_media.dart' show requireRehearsal;

const _cases = {
  'verifying': (StoreAuthority.legacy, AuthorityReason.interruptedStaging),
  'ready': (StoreAuthority.legacy, AuthorityReason.verifiedStaging),
  'fenceCreated': (StoreAuthority.recovery, AuthorityReason.invalidFence),
  'handoffReserved': (
    StoreAuthority.recovery,
    AuthorityReason.interruptedHandoff,
  ),
  'receiptPending': (
    StoreAuthority.recovery,
    AuthorityReason.interruptedHandoff,
  ),
  'receiptCommitted': (StoreAuthority.recording, AuthorityReason.activated),
  'beforeFirstWrite': (StoreAuthority.recording, AuthorityReason.activated),
  'duringWrite': (StoreAuthority.recording, AuthorityReason.activated),
};

/// An external controller stops the actual app process at KILL_READY.
Future<void> runCutoverCase(String action, String point) async {
  final expected = _cases[point];
  if (expected == null || (action != 'arm' && action != 'resume')) {
    throw ArgumentError('Unknown late handoff case.');
  }
  final arm = action == 'arm';
  final support = await getApplicationSupportDirectory();
  final root = await Directory(
    p.join(support.path, 'release-crash', point),
  ).create(recursive: true);
  final docs = await Directory(p.join(root.path, 'Documents')).create();
  final workspace = Directory(p.join(root.path, 'attempt'));
  final prefs = await SharedPreferences.getInstance();
  Future<Map<String, Object?>> read() => readCpdLegacyPreferences(prefs);
  final original = [
    for (var id = 1; id <= 4; id++)
      CpdEntry(
        id: id,
        profession: 'Nursing',
        date: DateTime(2024, 7, id),
        title: 'Baseline $id',
        details: 'Resume fixture',
        hours: 1,
        minutes: id,
        deleted: id == 4,
        attachments: const [],
      ).toJson(),
  ];
  if (arm) {
    requireRehearsal(!await workspace.exists(), 'Use a fresh case directory.');
    await prefs.clear();
    await prefs.setStringList('entries_json_list', original);
    await prefs.setStringList('professions', ['Nursing']);
    await prefs.setInt('next_entry_id', 5);
  }
  final beforeRaw = encodeLegacySnapshot(await read());
  const scope = AuthorityScope.rehearsal;
  Future<void> pause(String checkpoint) async {
    if (arm && checkpoint == point) {
      debugPrintSynchronously('CPD_RELEASE_KILL_READY $point');
      await Future<void>.delayed(const Duration(minutes: 5));
      throw StateError('The process was not terminated.');
    }
  }

  final gate = LegacyWriteGate();
  final coordinator = CpdMigrationCoordinator(
    workspace: workspace,
    documents: docs,
    gate: gate,
    readLegacy: read,
    onCheckpoint: (report) => pause(report.phase.name),
    onRehearsalHandoff: (checkpoint) => pause(checkpoint.name),
  );
  if (arm) {
    final outcome = await coordinator.rehearseActivation();
    requireRehearsal(
      outcome.phase == MigrationPhase.rehearsalActivated,
      'Expected activation before the store at $point.',
    );
  } else {
    final before = await coordinator.startup.inspect(
      scope: scope,
      hasLegacyRecords: true,
    );
    requireRehearsal(
      (before.store, before.reason) == expected,
      '$point opened ${before.store.name}/${before.reason.name}.',
    );
    await coordinator.snapshot.verifyAgainstSource(await read(), docs);
    if (before.store == StoreAuthority.legacy) {
      requireRehearsal(
        (await coordinator.rehearseActivation()).phase ==
            MigrationPhase.rehearsalActivated,
        'Pre-fence retry did not activate.',
      );
    }
    if (before.store == StoreAuthority.recovery) {
      requireRehearsal(
        (await coordinator.rehearseActivation()).failure ==
                'handoff_requires_recovery' &&
            await coordinator.readReceipt() == null,
        'Uncertain handoff reopened a writer.',
      );
      final guarded = await coordinator.startup.resolveAndGuard(
        gate,
        scope: scope,
        hasLegacyRecords: true,
      );
      var rejected = false;
      try {
        await gate.write(() async {});
      } on StateError {
        rejected = true;
      }
      requireRehearsal(
        guarded.store == StoreAuthority.recovery && rejected,
        'Recovery did not close the legacy write gate.',
      );
      await _verifyNativeDatabase(coordinator.databasePath, 4);
      requireRehearsal(
        encodeLegacySnapshot(await read()) == beforeRaw,
        'Recovery changed the legacy source.',
      );
      _passed(point, expected, 4);
      return;
    }
  }

  final authority = await coordinator.startup.resolveAndGuard(
    gate,
    scope: scope,
    hasLegacyRecords: true,
  );
  requireRehearsal(
    authority.store == StoreAuthority.recording,
    'No authority.',
  );
  await pause('beforeFirstWrite');
  final receipt = (await coordinator.readReceipt())!;
  final db = await SqliteRecordingRepository.open(
    coordinator.databasePath,
    durableWrites: true,
  );
  try {
    final store = await SqliteCpdStore.openVerified(
      db,
      sourceId: receipt.sourceId,
      documents: docs,
    );
    if (arm && point == 'duringWrite') {
      final previousIds = (await db.loadAllRecords())
          .map((row) => row.id)
          .toSet();
      await store.createAndSave(
        profession: 'Nursing',
        date: DateTime(2024, 8, 1),
        title: 'Committed before termination',
        details: '',
        hours: 1,
        minutes: 0,
        attachments: const [],
      );
      final persisted = (await db.loadAllRecords()).singleWhere(
        (row) => !previousIds.contains(row.id),
      );
      await db.transaction((tx) async {
        await tx.setRecordDeleted(
          persisted.id,
          true,
          expectedVersion: persisted.version,
        );
        await tx.saveHostValue('release-probe', 'uncommitted', 'rollback');
        await pause('duringWrite');
      });
      throw StateError('The process was not terminated during a write.');
    }
    requireRehearsal(!arm, 'The requested checkpoint was skipped.');
    final rows = await store.loadAll();
    requireRehearsal(
      listEquals(rows.take(4).map((row) => row.toJson()).toList(), original) &&
          rows.length == (point == 'duringWrite' ? 5 : 4) &&
          (await db.loadHostState('release-probe')).isEmpty &&
          (rows.length == 4 ||
              (!rows.last.deleted &&
                  rows.last.title == 'Committed before termination')),
      'Restart lost or duplicated a record, or committed a partial write.',
    );
  } finally {
    await db.close();
  }
  // An explicit retry probe starts without a sealed gate, as it would in a
  // new process before startup selects its writer.
  final retry = CpdMigrationCoordinator(
    workspace: workspace,
    documents: docs,
    readLegacy: read,
    gate: LegacyWriteGate(),
  );
  requireRehearsal(
    (await retry.rehearseActivation()).phase ==
            MigrationPhase.rehearsalActivated &&
        (await retry.readReceipt())?.encode() == receipt.encode() &&
        encodeLegacySnapshot(await read()) == beforeRaw,
    'Retry changed the source or adoption receipt.',
  );
  final count = point == 'duringWrite' ? 5 : 4;
  await _verifyNativeDatabase(coordinator.databasePath, count);
  _passed(point, expected, count);
}

Future<void> _verifyNativeDatabase(String path, int records) async {
  // Opening the database lets native SQLite roll back an interrupted write.
  final db = await databaseFactory.openDatabase(path);
  try {
    requireRehearsal(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single ==
              'ok' &&
          (await db.rawQuery('PRAGMA foreign_key_check')).isEmpty &&
          (await db.rawQuery(
                'SELECT count(*) FROM records',
              )).single.values.single ==
              records &&
          (await db.rawQuery(
                'SELECT count(*) FROM import_snapshots',
              )).single.values.single ==
              1,
      'SQLite integrity, foreign keys or import counts differ.',
    );
  } finally {
    await db.close();
  }
}

void _passed(
  String point,
  (StoreAuthority, AuthorityReason) startup,
  int records,
) {
  debugPrintSynchronously(
    'CPD_RELEASE_RESTART_PASS ${jsonEncode({'checkpoint': point, 'startup': startup.$1.name, 'reason': startup.$2.name, 'records': records, 'integrity': 'ok', 'foreignKeyViolations': 0})}',
  );
}
