import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../cpd_compatibility/sqlite_cpd_store.dart';
import '../recording_engine/import_plan.dart';
import '../recording_engine/storage_authority.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'device_storage_capacity.dart';
import 'legacy_migration.dart';
import 'legacy_recovery_snapshot.dart';
import 'legacy_write_gate.dart';
import 'migration_report.dart';
import 'recovery_retention.dart';
import 'startup_migration_authority.dart';

enum _Purpose { verifyOnly, rehearsalActivation, productionActivation }

/// Explicitly invoked while the legacy app is quiescent. Construct with an
/// app-private attempt directory outside Documents. No startup caller or
/// production authority consumer is installed in Phase 3A.
final class CpdMigrationCoordinator {
  CpdMigrationCoordinator({
    required this.workspace,
    required this.documents,
    required this.readLegacy,
    AvailableStorage? availableStorage,
    LegacyWriteGate? gate,
    DateTime Function()? clock,
    this.onCheckpoint,
    this.authorityFence,
  }) : _available = availableStorage ?? availableDeviceStorage,
       _gate = gate ?? LegacyWriteGate.instance,
       _clock = clock ?? DateTime.now;

  final Directory workspace;
  final Directory documents;
  final Future<Map<String, Object?>> Function() readLegacy;
  final AvailableStorage _available;
  final LegacyWriteGate _gate;
  final DateTime Function() _clock;
  final Future<void> Function(MigrationReport)? onCheckpoint;
  final File? authorityFence;

  static final _openAttempts = <String>{};
  CpdStartupAuthority get startup =>
      CpdStartupAuthority(workspace, fence: authorityFence);

  /// Enabling this requires a separately reviewed code change. There is no
  /// environment flag, preference, remote toggle or migration-on-launch path.
  bool get productionActivationEnabled => false;

  String get databasePath => p.join(workspace.path, 'recording.sqlite');
  LegacyRecoverySnapshot get snapshot =>
      LegacyRecoverySnapshot(Directory(p.join(workspace.path, 'recovery')));
  File get _journal => File(p.join(workspace.path, 'report.json'));

  Future<MigrationReport> rehearse() => _run(_Purpose.verifyOnly);

  /// Exercises the same verification and authority commit using a receipt
  /// explicitly labelled rehearsal. The legacy write gate is then released.
  Future<MigrationReport> rehearseActivation() =>
      _run(_Purpose.rehearsalActivation);

  Future<MigrationReport> activateProduction() =>
      _run(_Purpose.productionActivation);

  /// Keep the staged database and recovery copy. Abandonment makes this
  /// attempt read-only and requires a fresh directory for a future rehearsal.
  Future<MigrationReport> abandonStaging() => _withAttempt(() async {
    final result = await startup.inspect(
      scope: AuthorityScope.rehearsal,
      hasLegacyRecords: true,
    );
    if (!recoveryActions(
      result,
    ).contains(StartupRecoveryAction.abandonStaging)) {
      throw StateError('Only an unactivated attempt can be abandoned.');
    }
    final saved = await _readJournal();
    return _publish(
      MigrationReport(
        MigrationPhase.abandoned,
        sourceId: saved?.sourceId,
        review: saved?.review ?? const [],
      ),
    );
  });

  /// Materialise a verified legacy snapshot for examination in a separate
  /// directory. This operation cannot change either live store or authority.
  Future<RestoredLegacySource> restoreForReview(Directory separateCopy) async {
    final target = p.join(
      await separateCopy.parent.resolveSymbolicLinks(),
      p.basename(separateCopy.path),
    );
    _assertSeparate(await documents.resolveSymbolicLinks(), target);
    _assertSeparate(p.normalize(workspace.absolute.path), target);
    return snapshot.restoreTo(separateCopy);
  }

  Future<MigrationReport?> lastReport() async {
    final saved = await _readJournal();
    final receipt = await readReceipt();
    if (receipt == null) return saved;
    if (saved?.sourceId != receipt.sourceId) {
      throw StateError('The migration receipt and journal do not match.');
    }
    return MigrationReport(
      receipt.rehearsal
          ? MigrationPhase.rehearsalActivated
          : MigrationPhase.productionActivated,
      sourceId: receipt.sourceId,
      review: saved!.review,
    );
  }

  /// Separate read-only connection so inspection cannot close or reuse an
  /// application writer's connection.
  Future<MigrationReceipt?> readReceipt() async {
    final file = File(databasePath);
    if (!await file.exists() || await file.length() == 0) return null;
    final db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'host_state'],
      );
      if (tables.isEmpty) return null;
      final rows = await db.query(
        'host_state',
        where: 'namespace = ? AND key = ?',
        whereArgs: [migrationAuthorityNamespace, migrationAuthorityKey],
      );
      if (rows.isEmpty) return null;
      return MigrationReceipt.decode(rows.single['value'] as String);
    } finally {
      await db.close();
    }
  }

  /// Review callers can retrieve the exact original string even when the
  /// planner could not decode it. Raw content stays out of status reports.
  Future<Object?> readOriginalRow(int index) async {
    final recovered = await snapshot.readVerifiedSource();
    final rows = recovered.values['entries_json_list'];
    if (rows is! List) throw StateError('The source record list needs review.');
    return rows[index];
  }

  Future<RecoveryRetention> retention({
    bool activeStoreIntegrityConfirmed = false,
  }) async {
    try {
      final receipt = await readReceipt();
      final report = await lastReport();
      if (receipt == null && await startup.fence.exists()) {
        return RecoveryRetention.keepUntilIntegrityConfirmed;
      }
      final authority = receipt == null
          ? null
          : await startup.inspect(
              scope: receipt.rehearsal
                  ? AuthorityScope.rehearsal
                  : AuthorityScope.production,
              hasLegacyRecords: true,
            );
      final snapshotMatches =
          receipt != null &&
          authority?.store == StoreAuthority.recording &&
          await snapshot.verify() == receipt.snapshotFingerprint;
      return recoveryRetention(
        receipt: receipt,
        now: _clock(),
        integrityConfirmed: activeStoreIntegrityConfirmed && snapshotMatches,
        unresolved:
            report == null ||
            report.review.any(
              (issue) =>
                  _requiresResolution(issue) ||
                  issue.code == 'unresolved_attachment',
            ),
      );
    } catch (_) {
      return RecoveryRetention.keepUntilIntegrityConfirmed;
    }
  }

  Future<MigrationReport> _run(_Purpose purpose) async {
    if (purpose == _Purpose.productionActivation &&
        !productionActivationEnabled) {
      return const MigrationReport(MigrationPhase.disabled);
    }
    return _withAttempt(() => _prepare(purpose));
  }

  Future<T> _withAttempt<T>(Future<T> Function() run) async {
    final source = await documents.resolveSymbolicLinks();
    final requested = p.normalize(workspace.absolute.path);
    // Resolve the existing parent before creating any migration paths.
    final parent = await workspace.parent.resolveSymbolicLinks();
    final planned = p.join(parent, p.basename(requested));
    _assertSeparate(source, planned);
    _assertSeparate(p.normalize(documents.absolute.path), requested);
    if (await FileSystemEntity.type(requested, followLinks: false) ==
        FileSystemEntityType.link) {
      throw ArgumentError(
        'Use a real application-private migration directory.',
      );
    }
    await workspace.create();
    final root = await workspace.resolveSymbolicLinks();
    _assertSeparate(source, root);
    final pointedFence = p.join(
      await startup.fence.parent.resolveSymbolicLinks(),
      p.basename(startup.fence.path),
    );
    _assertSeparate(source, pointedFence);
    _assertSeparate(root, pointedFence);
    if (!_openAttempts.add(root)) {
      throw StateError('A migration attempt is already running.');
    }
    RandomAccessFile? lock;
    try {
      final file = File(p.join(root, 'migration.lock'));
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('The migration lock path is invalid.');
      }
      lock = await file.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      return await _gate.freeze(run);
    } finally {
      try {
        await lock?.close();
      } finally {
        _openAttempts.remove(root);
      }
    }
  }

  Future<MigrationReport> _prepare(_Purpose purpose) async {
    String? sourceId;
    var review = <RecoveryIssue>[];
    SqliteRecordingRepository? db;
    try {
      final prior = await _readJournal();
      final scope = purpose == _Purpose.productionActivation
          ? AuthorityScope.production
          : AuthorityScope.rehearsal;
      if (prior?.phase == MigrationPhase.abandoned) {
        return prior!;
      }
      final fenceType = await FileSystemEntity.type(
        startup.fence.path,
        followLinks: false,
      );
      if (fenceType != FileSystemEntityType.notFound) {
        if (scope == AuthorityScope.production) _gate.seal();
        if (fenceType != FileSystemEntityType.file ||
            purpose == _Purpose.verifyOnly) {
          throw StateError('A handoff is already reserved.');
        }
      }
      final receipt = await readReceipt();
      if (receipt == null &&
          (fenceType != FileSystemEntityType.notFound ||
              prior?.phase == MigrationPhase.handoffReserved ||
              prior?.phase == MigrationPhase.productionActivated ||
              prior?.phase == MigrationPhase.rehearsalActivated)) {
        // The destination may have accepted writes before its receipt was lost.
        // Even explicit retry cannot rebuild it from the legacy source.
        return MigrationReport(
          MigrationPhase.failed,
          sourceId: prior?.sourceId,
          failure: 'handoff_requires_recovery',
          review: prior?.review ?? const [],
        );
      }

      if (receipt != null) {
        final authority = await startup.inspect(
          scope: scope,
          hasLegacyRecords: true,
        );
        if (authority.store != StoreAuthority.recording) {
          throw StateError(
            'The existing authority cannot be reopened in this attempt.',
          );
        }
        return (await lastReport())!;
      }
      final values = await readLegacy();
      sourceId = SyntheticCpdMigration.sourceIdentity(values);
      if (prior?.sourceId != null && prior!.sourceId != sourceId) {
        // Leave the earlier report and its recovery copy addressable.
        return MigrationReport(
          MigrationPhase.failed,
          sourceId: prior.sourceId,
          failure: 'source_changed_new_attempt_required',
          review: prior.review,
        );
      }

      final rawBytes = utf8.encode(encodeLegacySnapshot(values)).length;
      final rows = values['entries_json_list'];
      final recordCount = rows is List ? rows.length : 0;
      // Includes raw inventory, hosted CPD projection, indexes and an
      // allocation reserve for SQLite journals and temporary work.
      final sqliteReserve =
          32 * 1024 * 1024 + rawBytes * 8 + recordCount * 8192;
      final hasSnapshot = await snapshot.directory.exists();
      final total =
          sqliteReserve +
          (hasSnapshot
              ? 0
              : await LegacyRecoverySnapshot.estimateBytes(values, documents));
      final free = await _available(workspace);
      await _publish(
        MigrationReport(
          MigrationPhase.checkingStorage,
          sourceId: sourceId,
          requiredBytes: total,
          availableBytes: free,
        ),
      );
      if (free < total) throw InsufficientRecoveryStorage(total, free);
      if (!hasSnapshot) {
        await _publish(
          MigrationReport(MigrationPhase.copyingRecovery, sourceId: sourceId),
        );
        await LegacyRecoverySnapshot.capture(
          legacyValues: values,
          documents: documents,
          destination: snapshot.directory,
          availableBytes: _available,
        );
      }
      final fingerprint = await snapshot.verifyAgainstSource(values, documents);
      await _publish(
        MigrationReport(MigrationPhase.snapshotReady, sourceId: sourceId),
      );
      final remaining = await _available(workspace);
      if (remaining < sqliteReserve) {
        throw InsufficientRecoveryStorage(sqliteReserve, remaining);
      }

      await _publish(
        MigrationReport(MigrationPhase.staging, sourceId: sourceId),
      );
      if (await snapshot.verifyAgainstSource(await readLegacy(), documents) !=
          fingerprint) {
        throw StateError('The recovery copy changed before import.');
      }
      db = await SqliteRecordingRepository.open(databasePath);
      final migration = SyntheticCpdMigration(db, documents);
      final plan = await migration.plan(values);
      final metadata = jsonDecode(plan.metadata) as Map;
      review = [
        for (final issue in metadata['issues'] as List)
          RecoveryIssue.fromPlanner(issue as Map),
        for (final _ in await snapshot.excludedPaths())
          const RecoveryIssue(
            'excluded_owned_evidence_path',
            RecoveryDisposition.requiresResolution,
          ),
      ];
      await migration.capture(values);
      final status = await db.stageImport(plan);
      if (status == ImportStatus.blocked || review.any(_requiresResolution)) {
        return await _publish(
          MigrationReport(
            MigrationPhase.reviewRequired,
            sourceId: sourceId,
            review: review,
          ),
        );
      }

      await _publish(
        MigrationReport(
          MigrationPhase.verifying,
          sourceId: sourceId,
          review: review,
        ),
      );
      await migration.verifyPlan(plan);
      final projection = await SqliteCpdStore.openVerified(
        db,
        sourceId: sourceId,
        documents: documents,
      );
      await projection.verifyLegacyProjection(values);
      if (await snapshot.verifyAgainstSource(await readLegacy(), documents) !=
          fingerprint) {
        throw StateError(
          'The source or recovery copy changed before verification.',
        );
      }
      final ready = await _publish(
        MigrationReport(
          MigrationPhase.ready,
          sourceId: sourceId,
          review: review,
        ),
      );
      if (purpose == _Purpose.verifyOnly) return ready;
      final binding = await _reserveHandoff(sourceId, fingerprint, scope);
      await _publish(
        MigrationReport(
          MigrationPhase.handoffReserved,
          sourceId: sourceId,
          review: review,
        ),
      );
      final activated = await _recordActivation(db, binding);
      // SQLite's receipt is authoritative if the process stops here. The
      // ready journal already contains matching source and review information.
      return MigrationReport(
        activated.rehearsal
            ? MigrationPhase.rehearsalActivated
            : MigrationPhase.productionActivated,
        sourceId: sourceId,
        review: review,
      );
    } catch (error) {
      final capacity = error is InsufficientRecoveryStorage ? error : null;
      final storageError =
          capacity != null ||
          error is RecordingStorageFull ||
          (error is FileSystemException && error.osError?.errorCode == 28);
      final failure = MigrationReport(
        MigrationPhase.failed,
        sourceId: sourceId,
        failure: storageError
            ? 'insufficient_storage'
            : 'verification_or_io_failed',
        requiredBytes: capacity?.requiredBytes,
        availableBytes: capacity?.availableBytes,
        review: review,
      );
      // Capacity or filesystem failures may also prevent a progress update.
      // The preceding journal and all independent recovery artifacts remain.
      final fenceReserved =
          await FileSystemEntity.type(startup.fence.path, followLinks: false) !=
          FileSystemEntityType.notFound;
      if (fenceReserved && purpose == _Purpose.productionActivation) {
        _gate.seal();
      }
      if (sourceId != null && !fenceReserved) {
        try {
          await _writeJournal(failure);
        } on FileSystemException {
          return failure;
        }
      }
      return failure;
    } finally {
      await db?.close();
    }
  }

  Future<AuthorityBinding> _reserveHandoff(
    String sourceId,
    String fingerprint,
    AuthorityScope scope,
  ) async {
    final fence = startup.fence;
    final binding = AuthorityBinding(
      id: const Uuid().v4(),
      sourceId: sourceId,
      snapshotFingerprint: fingerprint,
      scope: scope,
    );
    // Exclusive creation is intentional. Even a partial fence left by a
    // terminated writer makes startup fail closed.
    await fence.create(exclusive: true);
    if (scope == AuthorityScope.production) _gate.seal();
    await fence.writeAsString(binding.encode(), flush: true);
    return binding;
  }

  Future<MigrationReceipt> _recordActivation(
    SqliteRecordingRepository db,
    AuthorityBinding binding,
  ) => db.transaction((tx) async {
    final snap = await tx.loadImportSnapshot(binding.sourceId);
    final verifiedAt = snap?.verifiedAt;
    final now = _clock().toUtc();
    if (snap?.status != ImportStatus.verified ||
        verifiedAt == null ||
        now.isBefore(verifiedAt) ||
        (await tx.loadHostState(migrationAuthorityNamespace)).isNotEmpty) {
      throw StateError(
        'An independently verified import is required for activation.',
      );
    }
    final receipt = MigrationReceipt(
      sourceId: binding.sourceId,
      snapshotFingerprint: binding.snapshotFingerprint,
      verifiedAt: verifiedAt,
      activatedAt: now,
      rehearsal: binding.scope == AuthorityScope.rehearsal,
      bindingId: binding.id,
    );
    await tx.saveHostValue(
      migrationAuthorityNamespace,
      migrationAuthorityKey,
      receipt.encode(),
    );
    return receipt;
  });

  Future<MigrationReport?> _readJournal() async => await _journal.exists()
      ? MigrationReport.decode(await _journal.readAsString())
      : null;

  Future<MigrationReport> _publish(MigrationReport report) async {
    await _writeJournal(report);
    await onCheckpoint?.call(report);
    return report;
  }

  Future<void> _writeJournal(MigrationReport report) async {
    final pending = File(p.join(workspace.path, '.report.pending'));
    await pending.writeAsString(report.encode(), flush: true);
    await pending.rename(_journal.path);
  }
}

bool _requiresResolution(RecoveryIssue issue) =>
    issue.disposition == RecoveryDisposition.requiresResolution;

void _assertSeparate(String documents, String workspace) {
  if (p.equals(workspace, documents) ||
      p.isWithin(workspace, documents) ||
      p.isWithin(documents, workspace)) {
    throw ArgumentError(
      'The migration workspace must be separate from Documents.',
    );
  }
}
