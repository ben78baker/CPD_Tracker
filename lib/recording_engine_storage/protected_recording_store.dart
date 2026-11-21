import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'managed_attachment_files.dart';
import 'portable_archive.dart';
import 'sqlite_recording_repository.dart';

enum ProtectedWriteStage { pending, committed, checkpointed }

/// A synthetic, explicit composition root for acknowledged-write recovery.
/// Every mutation must enter through this owner. Keep live, checkpoint and
/// portable files separate and keep writers closed outside of callbacks.
class ProtectedRecordingStore {
  ProtectedRecordingStore({
    required this.live,
    required this.recovery,
    required this.backup,
    this.onStage,
  }) {
    final source = p.normalize(live.directory.absolute.path);
    final target = p.normalize(recovery.absolute.path);
    if (p.equals(source, target) ||
        p.isWithin(source, target) ||
        p.isWithin(target, source)) {
      throw ArgumentError('Use a separate recovery directory.');
    }
  }

  final RecordingWorkspace live;
  final Directory recovery;

  /// Pass a local recovery policy here. Use a separate, sanitising policy for
  /// user-portable export and for user-selected restore.
  final SqliteRecordingBackup backup;
  final Future<void> Function(ProtectedWriteStage)? onStage;
  static final _heldRoots = <String>{};
  static final _checkpointName = RegExp(
    r'^checkpoint-([0-9]+)\.recordingbackup$',
  );
  File get _head => File(p.join(recovery.path, 'authority.json'));

  File _checkpoint(int sequence) =>
      File(p.join(recovery.path, 'checkpoint-$sequence.recordingbackup'));

  /// Enrol a new rehearsal workspace or an explicitly verified migration
  /// candidate. An existing or interrupted authority requires review.
  Future<void> enrol() => _exclusive(() async {
    if (await _head.exists() ||
        await recovery.list().any(
          (entity) => p.basename(entity.path).startsWith('checkpoint-'),
        )) {
      throw StateError('Recording recovery already has an authority history.');
    }
    await _publish(_Fence(0, null, pending: true));
    final verified = await _capture(_checkpoint(1));
    await _publish(_Fence(1, verified.seal));
  });

  /// Record/evidence changes are enclosed by a pending fence and a verified
  /// independent checkpoint. Callers receive success only after publication.
  /// Do not keep the repository or attachment accessor beyond the callback.
  Future<T> write<T>(
    Future<T> Function(SqliteRecordingRepository, ManagedAttachmentFiles)
    mutate,
  ) => _exclusive(() async {
    final head = await _readFence();
    final previous = await _verified(head);
    if (head.pending) _needsReview();
    await _verifyLive(previous);
    await _publish(_Fence(head.sequence, head.seal, pending: true));
    await onStage?.call(ProtectedWriteStage.pending);

    final repository = await _open();
    final T result;
    try {
      await repository.configureProtectedWrites();
      result = await mutate(repository, ManagedAttachmentFiles(live.originals));
    } finally {
      await repository.close();
    }
    await onStage?.call(ProtectedWriteStage.committed);
    final verified = await _capture(_checkpoint(head.sequence + 1));
    await onStage?.call(ProtectedWriteStage.checkpointed);
    await _publish(_Fence(head.sequence + 1, verified.seal));
    return result;
  });

  /// Checks exact data, including evidence. Corruption or uncertain progress
  /// blocks further writes and leaves both the source and recovery files intact.
  Future<BackupInspection> verifyCurrent() => _exclusive(() async {
    final head = await _readFence();
    if (head.pending) _needsReview();
    final verified = await _verified(head);
    await _verifyLive(verified);
    return verified;
  });

  Future<BackupInspection> createPortable(
    SqliteRecordingBackup portable,
    File destination,
  ) => _exclusive(() async {
    final head = await _readFence();
    if (head.pending) _needsReview();
    await _verifyLive(await _verified(head));
    final repository = await _open();
    try {
      return await portable.create(
        repository: repository,
        originals: live.originals,
        destination: destination,
      );
    } finally {
      await repository.close();
    }
  });

  /// Prepare an isolated replacement after confirming the original is still
  /// recoverable. Leave both the authority fence and live workspace intact.
  Future<RecordingWorkspace> prepareReplacement({
    required SqliteRecordingBackup portable,
    required File source,
    required BackupInspection inspection,
    required Directory destination,
  }) => _exclusive(() async {
    final head = await _readFence();
    if (head.pending) _needsReview();
    await _verifyLive(await _verified(head));
    return portable.restore(
      source: source,
      inspection: inspection,
      destination: destination,
    );
  });

  /// Recover the last acknowledged state into an independent review workspace.
  /// This deliberately has no authority to replace an interrupted live store.
  Future<RecordingWorkspace> recoverAcknowledged(Directory destination) =>
      _exclusive(() async {
        final head = await _readFence();
        return backup.restore(
          source: _checkpoint(head.sequence),
          inspection: await _verified(head),
          destination: destination,
        );
      });

  Future<void> _verifyLive(BackupInspection acknowledged) async {
    final scratch = await recovery.createTemp('.check-live-');
    try {
      final copy = await _capture(
        File(p.join(scratch.path, 'comparison')),
        created: acknowledged.created,
      );
      if (copy.seal != acknowledged.seal) _needsReview();
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  Future<SqliteRecordingRepository> _open() async {
    if (await FileSystemEntity.type(live.databasePath, followLinks: false) !=
        FileSystemEntityType.file) {
      _needsReview();
    }
    return SqliteRecordingRepository.open(
      live.databasePath,
      factory: backup.factory,
    );
  }

  Future<BackupInspection> _capture(
    File destination, {
    DateTime? created,
  }) async {
    final repository = await _open();
    try {
      return await backup.create(
        repository: repository,
        originals: live.originals,
        destination: destination,
        created: created,
      );
    } finally {
      await repository.close();
    }
  }

  Future<BackupInspection> _verified(_Fence head) async {
    if (head.sequence < 1 || head.seal == null) _needsReview();
    final copy = await backup.inspect(_checkpoint(head.sequence));
    if (copy.seal != head.seal) _needsReview();
    // An independently retained higher checkpoint signals an interrupted
    // publication or a stale fence. Never silently prefer an older state.
    final maximum = head.sequence + (head.pending ? 1 : 0);
    await for (final entity in recovery.list(followLinks: false)) {
      final match = _checkpointName.firstMatch(p.basename(entity.path));
      if (match != null && (int.tryParse(match[1]!) ?? maximum + 1) > maximum) {
        _needsReview();
      }
    }
    return copy;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    await recovery.create(recursive: true);
    final target = await recovery.resolveSymbolicLinks();
    final source = await live.directory.resolveSymbolicLinks();
    if (p.equals(source, target) ||
        p.isWithin(source, target) ||
        p.isWithin(target, source)) {
      throw ArgumentError('Recovery must be outside the live store.');
    }
    if (_heldRoots.contains(target) || _heldRoots.contains(source)) {
      _needsReview();
    }
    _heldRoots.addAll([target, source]);
    try {
      final lock = await File(
        p.join(source, 'writer.lock'),
      ).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
        return await action();
      } finally {
        await lock.close();
      }
    } finally {
      _heldRoots.removeAll([target, source]);
    }
  }

  Future<_Fence> _readFence() async {
    try {
      if (await _head.length() > 1024) _needsReview();
      final data = jsonDecode(await _head.readAsString()) as Map;
      final sequence = data['sequence'] as int;
      final seal = data['seal'] as String?;
      if (data['version'] != 1 ||
          sequence < 0 ||
          sequence > 1000000000 ||
          sequence > 0 &&
              (seal == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(seal))) {
        _needsReview();
      }
      return _Fence(sequence, seal, pending: data['pending'] as bool);
    } catch (_) {
      _needsReview();
    }
  }

  Future<void> _publish(_Fence fence) async {
    final staging = await recovery.createTemp('.authority-');
    try {
      final pending = File(p.join(staging.path, 'head.json'));
      await pending.writeAsString(
        jsonEncode({
          'version': 1,
          'sequence': fence.sequence,
          'seal': fence.seal,
          'pending': fence.pending,
        }),
        flush: true,
      );
      await pending.rename(_head.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Never _needsReview() =>
      throw StateError('Recording authority needs recovery review.');
}

class _Fence {
  const _Fence(this.sequence, this.seal, {this.pending = false});
  final int sequence;
  final String? seal;
  final bool pending;
}
