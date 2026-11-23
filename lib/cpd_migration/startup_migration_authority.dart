import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../recording_engine/storage_authority.dart';
import '../recording_engine_storage/original_directory_sync.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'legacy_recovery_snapshot.dart';
import 'legacy_write_gate.dart';
import 'migration_report.dart';
import 'recovery_retention.dart';

const migrationAuthorityNamespace = 'cpd.migration';
const migrationAuthorityKey = 'authority';
const migrationPendingKey = 'pending';

/// Boot-time read-only adapter. Production startup does not call it in this
/// phase. A future composition root must run it before creating any writer.
class CpdStartupAuthority {
  CpdStartupAuthority(this.workspace, {File? fence})
    : fence =
          fence ??
          File(
            p.join(
              workspace.parent.path,
              '${p.basename(workspace.path)}.authority.json',
            ),
          );

  final Directory workspace;
  final File fence;
  File get writerReleased => File('${fence.path}.released');
  File get database => File(p.join(workspace.path, 'recording.sqlite'));
  File get journal => File(p.join(workspace.path, 'report.json'));
  LegacyRecoverySnapshot get backup =>
      LegacyRecoverySnapshot(Directory(p.join(workspace.path, 'recovery')));

  Future<StartupAuthority> resolveAndGuard(
    LegacyWriteGate gate, {
    required AuthorityScope scope,
    required bool hasLegacyRecords,
    bool allowSharedWritesForRecording = false,
  }) => gate.freeze(
    () => guardFrozen(
      gate,
      scope: scope,
      hasLegacyRecords: hasLegacyRecords,
      allowSharedWritesForRecording: allowSharedWritesForRecording,
    ),
  );

  /// Use only while the caller holds the legacy write gate frozen.
  Future<StartupAuthority> guardFrozen(
    LegacyWriteGate gate, {
    required AuthorityScope scope,
    required bool hasLegacyRecords,
    bool allowSharedWritesForRecording = false,
  }) async {
    try {
      final state = await inspect(
        scope: scope,
        hasLegacyRecords: hasLegacyRecords,
      );
      if (state.store != StoreAuthority.legacy) {
        if (state.store == StoreAuthority.recording) {
          await markWriterReleased();
        }
        gate.seal(
          allowSharedWrites:
              state.store == StoreAuthority.recording &&
              allowSharedWritesForRecording,
        );
      }
      return state;
    } catch (_) {
      gate.seal();
      rethrow;
    }
  }

  /// Independent of SQLite. Once present, even an older copy of a database
  /// containing a pending handoff cannot prove that no writer was opened.
  Future<void> markWriterReleased() async {
    final marker = writerReleased;
    if (!await _exists(marker)) await marker.create(exclusive: true);
    await syncOriginalDirectory(marker.parent);
  }

  Future<bool> hasWriterRelease() async =>
      await FileSystemEntity.type(writerReleased.path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<StartupAuthority> inspect({
    required AuthorityScope scope,
    required bool hasLegacyRecords,
  }) async {
    final workspaceType = await FileSystemEntity.type(
      workspace.path,
      followLinks: false,
    );
    if (workspaceType != FileSystemEntityType.notFound &&
        workspaceType != FileSystemEntityType.directory) {
      return const StartupAuthority(
        StoreAuthority.recovery,
        AuthorityReason.inconsistentEvidence,
        RecoveryCopyState.unchecked,
      );
    }
    MigrationReport? progress;
    var progressValid = true;
    var journalExists = false;
    try {
      journalExists = await _exists(journal);
      if (journalExists) {
        progress = MigrationReport.decode(await journal.readAsString());
      }
    } catch (_) {
      progressValid = false;
    }
    AuthorityBinding? binding;
    var fenceState = ArtifactState.absent;
    try {
      if (await _exists(fence)) {
        fenceState = ArtifactState.invalid;
        binding = AuthorityBinding.decode(await fence.readAsString());
        fenceState = ArtifactState.valid;
      }
    } catch (_) {
      fenceState = ArtifactState.invalid;
    }
    final destination = await _inspectDestination();
    var recovery = RecoveryCopyState.absent;
    try {
      if (await _exists(backup.directory)) {
        recovery = RecoveryCopyState.damaged;
        final fingerprint = await backup.verifyManifest();
        if (binding == null || fingerprint == binding.snapshotFingerprint) {
          recovery = RecoveryCopyState.manifestVerified;
        }
      }
    } catch (_) {
      recovery = RecoveryCopyState.damaged;
    }
    return resolveStartupAuthority(
      StartupAuthorityEvidence(
        scope: scope,
        hasLegacyRecords: hasLegacyRecords,
        hasAttempt:
            journalExists ||
            recovery != RecoveryCopyState.absent ||
            destination.state != ArtifactState.absent &&
                progressValid &&
                progress != null,
        stageVerified: progress?.phase == MigrationPhase.ready,
        stageAbandoned: progress?.phase == MigrationPhase.abandoned,
        journalValid: progressValid,
        journalClaimsActivation:
            await hasWriterRelease() ||
            progress?.phase == MigrationPhase.handoffReserved ||
            progress?.phase == MigrationPhase.productionActivated ||
            progress?.phase == MigrationPhase.rehearsalActivated,
        fenceState: fenceState,
        fence: binding,
        databaseState: destination.state,
        databaseVersionSupported: destination.versionSupported,
        receiptState: destination.receiptState,
        receipt: destination.binding,
        destinationMatches: destination.verified,
        recoveryCopy: recovery,
      ),
    );
  }

  Future<_Destination> _inspectDestination() async {
    Database? db;
    try {
      if (!await _exists(database)) {
        return const _Destination(ArtifactState.absent);
      }
      if (await database.length() == 0) {
        return const _Destination(ArtifactState.invalid);
      }
      db = await databaseFactory.openDatabase(
        database.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version =
          (await db.rawQuery('PRAGMA user_version')).single.values.single
              as int;
      if (version > SqliteRecordingRepository.schemaVersion || version < 1) {
        return const _Destination(ArtifactState.valid, versionSupported: false);
      }
      final integrity = await db.rawQuery('PRAGMA quick_check(1)');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        return const _Destination(ArtifactState.invalid);
      }
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'host_state'],
      );
      if (tables.isEmpty) return const _Destination(ArtifactState.valid);
      final rows = await db.query(
        'host_state',
        columns: ['value'],
        where: 'namespace = ? AND key = ?',
        whereArgs: [migrationAuthorityNamespace, migrationAuthorityKey],
      );
      if (rows.isEmpty) return const _Destination(ArtifactState.valid);
      try {
        final pending = await db.query(
          'host_state',
          where: 'namespace = ? AND key = ?',
          whereArgs: [migrationAuthorityNamespace, migrationPendingKey],
        );
        if (pending.isNotEmpty) {
          return const _Destination(
            ArtifactState.valid,
            receiptState: ArtifactState.invalid,
          );
        }
        final receipt = MigrationReceipt.decode(rows.single['value'] as String);
        final binding = AuthorityBinding(
          id: receipt.bindingId!,
          sourceId: receipt.sourceId,
          snapshotFingerprint: receipt.snapshotFingerprint,
          scope: receipt.rehearsal
              ? AuthorityScope.rehearsal
              : AuthorityScope.production,
        );
        final snapshots = await db.query(
          'import_snapshots',
          columns: ['status', 'verified_at'],
          where: 'source_id = ?',
          whereArgs: [receipt.sourceId],
        );
        final origin = await db.query(
          'host_state',
          columns: ['value'],
          where: 'namespace = ? AND key = ?',
          whereArgs: ['cpd.preferences', 'source'],
        );
        final verified =
            snapshots.length == 1 &&
            snapshots.single['status'] == 'verified' &&
            DateTime.tryParse(
                  snapshots.single['verified_at'] as String? ?? '',
                ) ==
                receipt.verifiedAt &&
            !receipt.activatedAt.isBefore(receipt.verifiedAt) &&
            origin.length == 1 &&
            origin.single['value'] == receipt.sourceId;
        return _Destination(
          ArtifactState.valid,
          receiptState: ArtifactState.valid,
          binding: binding,
          verified: verified,
        );
      } catch (_) {
        return const _Destination(
          ArtifactState.valid,
          receiptState: ArtifactState.invalid,
        );
      }
    } catch (_) {
      return const _Destination(ArtifactState.invalid);
    } finally {
      await db?.close();
    }
  }
}

Future<bool> _exists(FileSystemEntity entity) async {
  final type = await FileSystemEntity.type(entity.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return false;
  if (type !=
      (entity is Directory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file)) {
    throw StateError('Unexpected migration artifact type.');
  }
  return true;
}

class _Destination {
  const _Destination(
    this.state, {
    this.versionSupported = true,
    this.receiptState = ArtifactState.absent,
    this.binding,
    this.verified = false,
  });
  final ArtifactState state;
  final bool versionSupported;
  final ArtifactState receiptState;
  final AuthorityBinding? binding;
  final bool verified;
}
