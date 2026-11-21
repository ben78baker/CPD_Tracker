import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_rehearsal_page.dart';
import 'package:cpd_tracker/cpd_migration/startup_migration_authority.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/recovery_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'phase3b_rehearsal_app.dart' show openSyntheticRehearsal;

void _check(bool valid, String check) {
  if (!valid) throw StateError(check);
}

Future<StartupAuthority> _boot(CpdMigrationCoordinator attempt) => attempt
    .startup
    .inspect(scope: AuthorityScope.rehearsal, hasLegacyRecords: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('Testing migration authority'),
    ),
  );
  try {
    await _abandon();
    await _interruptedFence();
    await _competingHandoffs();
    await _active();
    debugPrintSynchronously('CPD_PHASE3B_AUTHORITY_PASS');
  } catch (error, stack) {
    debugPrintSynchronously('CPD_PHASE3B_AUTHORITY_FAIL $error\n$stack');
    rethrow;
  }
}

Future<void> _abandon() async {
  final attempt = await openSyntheticRehearsal(
    RehearsalSample.standard,
    (_) async {},
  );
  final root = attempt.workspace.parent;
  try {
    _check(
      (await _boot(attempt)).reason == AuthorityReason.legacyInstallation,
      'Existing installation',
    );
    final read = await attempt.rehearse();
    _check(
      read.phase == MigrationPhase.ready &&
          read.review.single.code == 'unresolved_attachment',
      'Missing file does not prevent verification',
    );
    _check(
      (await _boot(attempt)).reason == AuthorityReason.verifiedStaging,
      'Verified staging still uses legacy',
    );
    final restored = await attempt.restoreForReview(
      Directory(p.join(root.path, 'examined-copy')),
    );
    _check(
      restored.values['professions'].toString() == '[Education]',
      'Independent verified restore',
    );
    await attempt.abandonStaging();
    _check(
      (await _boot(attempt)).reason == AuthorityReason.abandonedStaging,
      'Abandoned staging stays inactive',
    );
    _check(
      (await attempt.rehearseActivation()).phase == MigrationPhase.abandoned &&
          await attempt.startup.database.exists() &&
          await attempt.snapshot.directory.exists(),
      'Abandoned files were kept and retry blocked',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> _interruptedFence() async {
  final attempt = await openSyntheticRehearsal(RehearsalSample.standard, (
    report,
  ) async {
    if (report.phase == MigrationPhase.handoffReserved) {
      throw StateError('Synthetic interruption after fence');
    }
  });
  try {
    final outcome = await attempt.rehearseActivation();
    _check(
      outcome.phase == MigrationPhase.failed,
      'Interrupted handoff returned a failure',
    );
    final state = await _boot(attempt);
    _check(
      state.store == StoreAuthority.recovery &&
          state.reason == AuthorityReason.interruptedHandoff,
      'A fence without a receipt opens recovery only',
    );
    _check(
      (await attempt.rehearseActivation()).failure ==
              'handoff_requires_recovery' &&
          await attempt.readReceipt() == null,
      'Retry cannot reconstruct authority from the old source',
    );
  } finally {
    await attempt.workspace.parent.delete(recursive: true);
  }
}

Future<void> _competingHandoffs() async {
  final root = await Directory.systemTemp.createTemp('cpd_competing_handoffs_');
  final docs = await Directory(p.join(root.path, 'Documents')).create();
  final fence = File(p.join(root.path, 'one-authority.json'));
  CpdMigrationCoordinator contender(String name) => CpdMigrationCoordinator(
    workspace: Directory(p.join(root.path, name)),
    documents: docs,
    authorityFence: fence,
    gate: LegacyWriteGate(),
    readLegacy: () async => {},
    availableStorage: (_) async => 200 * 1024 * 1024,
  );
  try {
    final attempts = [contender('first'), contender('second')];
    final outcomes = await Future.wait(
      attempts.map((attempt) => attempt.rehearseActivation()),
    );
    _check(
      outcomes
              .where(
                (value) => value.phase == MigrationPhase.rehearsalActivated,
              )
              .length ==
          1,
      'Only one contender reserves independent authority',
    );
    final receipts = await Future.wait(
      attempts.map((attempt) => attempt.readReceipt()),
    );
    _check(
      receipts.where((receipt) => receipt != null).length == 1,
      'The other workspace cannot reuse the winning marker',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> _active() async {
  final attempt = await openSyntheticRehearsal(
    RehearsalSample.standard,
    (_) async {},
  );
  final root = attempt.workspace.parent;
  try {
    final activated = await attempt.rehearseActivation();
    _check(
      activated.phase == MigrationPhase.rehearsalActivated,
      'Synthetic activation committed',
    );
    final receipt = (await attempt.readReceipt())!;
    final gate = LegacyWriteGate();
    final state = await attempt.startup.resolveAndGuard(
      gate,
      scope: AuthorityScope.rehearsal,
      hasLegacyRecords: true,
    );
    _check(
      state.store == StoreAuthority.recording,
      'Boot opens SQLite for the bound scope',
    );
    var legacyWrite = false;
    try {
      await gate.write(() async => legacyWrite = true);
    } on StateError {
      // The legacy writer is sealed before a recording writer can open.
    }
    _check(!legacyWrite, 'Exclusive writer handoff');
    final db = await SqliteRecordingRepository.open(attempt.databasePath);
    try {
      final store = await SqliteCpdStore.openVerified(
        db,
        sourceId: activated.sourceId!,
        documents: attempt.documents,
      );
      const reference = 'attachments/new-evidence.txt';
      await File(
        p.join(attempt.documents.path, reference),
      ).writeAsString('New evidence');
      final created = await store.createAndSave(
        profession: 'Education',
        date: DateTime(2025, 4, 2),
        title: 'Activity after activation',
        details: 'New work',
        hours: 1,
        minutes: 30,
        attachments: [reference],
      );
      await store.updateEntry(
        CpdEntry.fromMap({
          ...created.toMap(),
          'details': 'Updated after activation',
        }),
      );
      await store.setDeleted(1, true);
    } finally {
      await db.close();
    }

    await File(
      p.join(attempt.snapshot.directory.path, 'manifest.json'),
    ).rename(p.join(root.path, 'damaged-preview-manifest.json'));
    final degraded = await _boot(attempt);
    _check(
      degraded.store == StoreAuthority.recording &&
          degraded.recoveryCopy == RecoveryCopyState.damaged,
      'Backup damage does not replace live data',
    );
    await attempt.startup.journal.writeAsString('{broken');
    _check(
      (await _boot(attempt)).store == StoreAuthority.recording,
      'Progress damage does not invalidate live authority',
    );
    final safe = await copyQuiescentRecordingFiles(
      database: attempt.startup.database,
      fence: attempt.startup.fence,
      destination: Directory(p.join(root.path, 'preserved')),
      originals: [Directory(p.join(attempt.documents.path, 'attachments'))],
    );
    final copy = await SqliteRecordingRepository.open(
      p.join(safe.path, 'recording.sqlite'),
    );
    try {
      final store = await SqliteCpdStore.openVerified(
        copy,
        sourceId: receipt.sourceId,
        documents: Directory(p.join(safe.path, 'originals')),
      );
      final rows = await store.loadAll();
      _check(
        rows.first.deleted &&
            rows.last.details == 'Updated after activation' &&
            rows.last.attachments.single == 'attachments/new-evidence.txt',
        'Current writes survive preservation',
      );
      _check(
        await File(
              p.join(safe.path, 'originals', rows.last.attachments.single),
            ).readAsString() ==
            'New evidence',
        'Post-activation evidence bytes preserved',
      );
    } finally {
      await copy.close();
    }

    final raw = await databaseFactory.openDatabase(attempt.databasePath);
    await raw.execute('PRAGMA user_version=999');
    await raw.close();
    _check(
      (await _boot(attempt)).reason == AuthorityReason.unsupportedDatabase,
      'Upgrade from newer schema is fail-closed',
    );
    final revert = await databaseFactory.openDatabase(attempt.databasePath);
    await revert.execute('PRAGMA user_version=3');
    await revert.delete(
      'host_state',
      where: 'namespace = ? AND key = ?',
      whereArgs: [migrationAuthorityNamespace, migrationAuthorityKey],
    );
    await revert.close();
    _check(
      (await _boot(attempt)).store == StoreAuthority.recovery &&
          (await attempt.rehearseActivation()).phase == MigrationPhase.failed,
      'Deleted receipt after acknowledged writes cannot recreate a stale store',
    );
    final damaged = await attempt.startup.database.rename(
      p.join(root.path, 'keep-original.sqlite'),
    );
    await attempt.startup.database.writeAsString('corrupt database');
    _check(
      (await _boot(attempt)).reason == AuthorityReason.invalidDatabase,
      'Corrupt SQLite blocks both writers',
    );
    await attempt.startup.database.delete();
    _check(
      (await _boot(attempt)).reason == AuthorityReason.missingDestination &&
          await damaged.exists(),
      'A missing live database never falls back',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
