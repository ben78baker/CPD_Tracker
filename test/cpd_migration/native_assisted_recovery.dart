import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/startup_migration_authority.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/recording_engine_storage/recovery_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'native_cutover_recovery.dart' show runCutoverCase;
import 'native_rehearsal_media.dart' show requireRehearsal;

const _scope = AuthorityScope.rehearsal;
const _original = 'attachments/owned.txt';

enum _Fault {
  corruptedDatabase,
  missingReceipt,
  damagedReceipt,
  damagedManifest,
  incompleteSnapshot,
  missingLiveAttachment,
  conflictingFence,
}

/// Runs against native SQLite and invented files inside a disposable app.
Future<void> main() async {
  if (kReleaseMode) throw UnsupportedError('Use an isolated debug build.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Center(
      child: Text(
        'Synthetic assisted recovery',
        textDirection: TextDirection.ltr,
      ),
    ),
  );
  final scratch = await Directory.systemTemp.createTemp('cpd_assisted_');
  try {
    final support = await getApplicationSupportDirectory();
    final command = File(p.join(support.path, 'assisted-command'));
    if (await command.exists()) {
      final action = (await command.readAsString()).trim();
      await command.delete();
      if (action == 'pause') {
        await runCutoverCase(
          'resume',
          'receiptPending',
          onProgress: (report) async {
            if (report.phase == MigrationPhase.verifying) {
              debugPrintSynchronously('CPD_ASSISTED_REVALIDATION_READY');
              await Future<void>.delayed(const Duration(minutes: 3));
              throw StateError('Expected a physical process termination.');
            }
          },
        );
      } else {
        await runCutoverCase(action, 'receiptPending');
      }
      return;
    }
    for (final fault in _Fault.values) {
      await _runFault(scratch, fault);
    }
    debugPrintSynchronously('CPD_ASSISTED_MATRIX_PASS');
  } on Object catch (error, stack) {
    debugPrintSynchronously('CPD_ASSISTED_MATRIX_FAIL $error\n$stack');
    rethrow;
  } finally {
    await scratch.delete(recursive: true);
  }
}

Future<void> _runFault(Directory scratch, _Fault fault) async {
  final root = await Directory(p.join(scratch.path, fault.name)).create();
  final documents = await Directory(p.join(root.path, 'Documents')).create();
  final evidence = File(p.join(documents.path, _original));
  await evidence.parent.create();
  await evidence.writeAsString('Synthetic original', flush: true);
  final originalFingerprint = await legacyFileFingerprint(evidence);
  final workspace = Directory(p.join(root.path, 'attempt'));
  final source = <String, Object?>{
    'professions': ['Practice', 'Archived'],
    'deleted_professions': ['Archived'],
    'targets_v1': '{"Practice":{"minutes":120,"cycle":"year"}}',
    'entries_json_list': [
      for (final (id, profession) in [(1, 'Practice'), (2, 'Archived')])
        CpdEntry(
          id: id,
          profession: profession,
          date: DateTime(2020, 2, 29),
          title: 'Private specimen title $id',
          details: 'Private specimen description',
          hours: 0,
          minutes: 45,
          deleted: id == 2,
          attachments: id == 1 ? [_original] : [],
        ).toJson(),
    ],
    'next_entry_id': 3,
  };
  final sourceDigest = encodeLegacySnapshot(source);
  CpdMigrationCoordinator open(LegacyWriteGate gate) => CpdMigrationCoordinator(
    workspace: workspace,
    documents: documents,
    gate: gate,
    readLegacy: () async => source,
  );
  final setup = open(LegacyWriteGate());
  final report = await setup.rehearseActivation();
  requireRehearsal(
    report.phase == MigrationPhase.rehearsalActivated,
    'Fixture adoption failed.',
  );
  final authority = setup.startup;
  final fingerprint = await setup.snapshot.verify();
  final originalReceipt = (await setup.readReceipt())!;
  final dbFile = File(setup.databasePath);
  final badBackup =
      fault == _Fault.damagedManifest || fault == _Fault.incompleteSnapshot;
  final soleCopyNeeded = fault == _Fault.missingLiveAttachment;

  // Evidence of a returned writer must survive a later loss of its receipt.
  final writable = await SqliteRecordingRepository.open(
    setup.databasePath,
    durableWrites: true,
  );
  try {
    final store = await SqliteCpdStore.openVerified(
      writable,
      sourceId: originalReceipt.sourceId,
      documents: documents,
    );
    await store.createAndSave(
      profession: 'Practice',
      date: DateTime(2025, 3, 16),
      title: 'Post-handoff row',
      details: '',
      hours: 1,
      minutes: 0,
      attachments: [],
    );
  } finally {
    await writable.close();
  }

  switch (fault) {
    case _Fault.corruptedDatabase:
      await dbFile.writeAsString('Invalid SQLite contents', flush: true);
    case _Fault.missingReceipt:
    case _Fault.damagedReceipt:
    case _Fault.damagedManifest:
    case _Fault.incompleteSnapshot:
    case _Fault.missingLiveAttachment:
      // The source copy cannot re-authorise the store after writer release.
      // Combine receipt loss with snapshot or original damage where applicable.
      final db = await SqliteRecordingRepository.open(setup.databasePath);
      try {
        if (fault == _Fault.damagedReceipt) {
          await db.saveHostValue(
            migrationAuthorityNamespace,
            migrationAuthorityKey,
            '{',
          );
        } else {
          await db.removeHostValue(
            migrationAuthorityNamespace,
            migrationAuthorityKey,
          );
        }
      } finally {
        await db.close();
      }
      if (fault == _Fault.damagedManifest) {
        await File(
          p.join(setup.snapshot.directory.path, 'manifest.json'),
        ).writeAsString('{', flush: true);
      }
      if (fault == _Fault.incompleteSnapshot) {
        await File(p.join(setup.snapshot.directory.path, _original)).delete();
      }
      if (soleCopyNeeded) await evidence.delete();
    case _Fault.conflictingFence:
      final fence = AuthorityBinding.decode(
        await authority.fence.readAsString(),
      );
      await authority.fence.writeAsString(
        AuthorityBinding(
          id: '${fence.id}-different',
          sourceId: fence.sourceId,
          snapshotFingerprint: fence.snapshotFingerprint,
          scope: _scope,
        ).encode(),
        flush: true,
      );
  }

  final databaseBefore = await backupDigest(dbFile);
  final fenceBefore = await authority.fence.readAsString();
  final expected = switch (fault) {
    _Fault.corruptedDatabase => AuthorityReason.invalidDatabase,
    _Fault.damagedReceipt => AuthorityReason.invalidReceipt,
    _Fault.conflictingFence => AuthorityReason.inconsistentEvidence,
    _ => AuthorityReason.interruptedHandoff,
  };
  for (var launch = 0; launch < 3; launch++) {
    final gate = LegacyWriteGate();
    final attempt = open(gate);
    final decision = await attempt.recoverRehearsalStartup();
    requireRehearsal(
      decision.store == StoreAuthority.recovery && decision.reason == expected,
      'Damaged store selected a writer for ${fault.name}.',
    );
    await _mustFail(() => gate.write(() async {}));
    await _mustFail(() => gate.writeShared(() async {}));
    requireRehearsal(
      await backupDigest(dbFile) == databaseBefore &&
          await authority.fence.readAsString() == fenceBefore &&
          await authority.hasWriterRelease(),
      'Recovery altered the preserved artifacts.',
    );
  }

  // The operator keeps the exact broken database and the surviving files.
  final coldCopy = await copyQuiescentRecordingFiles(
    database: dbFile,
    fence: authority.fence,
    destination: Directory(p.join(root.path, 'forensics')),
    originals: [evidence.parent],
  );
  requireRehearsal(
    await backupDigest(File(p.join(coldCopy.path, 'recording.sqlite'))) ==
        databaseBefore,
    'Forensic copy changed the database bytes.',
  );
  if (fault != _Fault.corruptedDatabase) {
    final inspection = await databaseFactory.openDatabase(
      p.join(coldCopy.path, 'recording.sqlite'),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      requireRehearsal(
        (await inspection.rawQuery(
                  'SELECT count(*) FROM records',
                )).single.values.single ==
                3 &&
            (await inspection.rawQuery(
                  'SELECT count(*) FROM import_snapshots',
                )).single.values.single ==
                1,
        'The separate database copy lost committed records or duplicated the import.',
      );
    } finally {
      await inspection.close();
    }
  }
  if (!soleCopyNeeded) {
    requireRehearsal(
      await legacyFileFingerprint(
            File(p.join(coldCopy.path, 'originals', _original)),
          ) ==
          originalFingerprint,
      'Available live original was not copied.',
    );
  }
  await _mustFail(
    () => copyQuiescentRecordingFiles(
      database: dbFile,
      fence: authority.fence,
      destination: coldCopy,
    ),
  );

  final reviewDocs = Directory(p.join(root.path, 'review-documents'));
  if (badBackup) {
    await _mustFail(() => setup.restoreForReview(reviewDocs));
    requireRehearsal(
      !await reviewDocs.exists(),
      'Incomplete recovery was published.',
    );
  } else {
    final restored = await setup.restoreForReview(reviewDocs);
    await _mustFail(() => setup.restoreForReview(reviewDocs));
    requireRehearsal(
      encodeLegacySnapshot(restored.values) == sourceDigest &&
          await setup.snapshot.verify() == fingerprint &&
          await legacyFileFingerprint(
                File(p.join(reviewDocs.path, _original)),
              ) ==
              originalFingerprint,
      'Independent copy failed recovery verification.',
    );
    final review = CpdMigrationCoordinator(
      workspace: Directory(p.join(root.path, 'review-attempt')),
      documents: reviewDocs,
      gate: LegacyWriteGate(),
      readLegacy: () async => restored.values,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await review.rehearse();
      requireRehearsal(
        result.phase == MigrationPhase.ready &&
            await review.readReceipt() == null,
        'Review created authority or could not be repeated.',
      );
    }
    final projected = await SqliteRecordingRepository.open(review.databasePath);
    try {
      final store = await SqliteCpdStore.openVerified(
        projected,
        sourceId: originalReceipt.sourceId,
        documents: reviewDocs,
      );
      await store.verifyLegacyProjection(restored.values);
      requireRehearsal(
        (await store.loadAll()).length == 2 &&
            (await store.loadDeleted()).length == 1 &&
            (await store.loadDeletedProfessions()).single == 'Archived',
        'Recovery duplicated rows or changed historical states.',
      );
    } finally {
      await projected.close();
    }
  }
  final finalState = await authority.inspect(
    scope: _scope,
    hasLegacyRecords: true,
  );
  requireRehearsal(
    finalState.store == StoreAuthority.recovery &&
        await backupDigest(dbFile) == databaseBefore &&
        encodeLegacySnapshot(source) == sourceDigest,
    'Review modified the active authority or source.',
  );
  debugPrintSynchronously(
    'CPD_ASSISTED_CASE ${jsonEncode({'fault': fault.name, 'authority': finalState.store.name, 'reason': finalState.reason.name, 'guardedStarts': 3, 'independentRestoreVerified': !badBackup})}',
  );
}

Future<void> _mustFail(Future<void> Function() run) async {
  try {
    await run();
  } on StateError {
    return;
  }
  throw StateError('An unsafe operation was allowed.');
}
