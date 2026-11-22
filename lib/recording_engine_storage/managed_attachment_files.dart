import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../recording_engine/models.dart';
import 'portable_archive.dart';

/// Stages originals independently of the database transaction. A failed save
/// leaves the staged original available for retry. Reclamation is a separate
/// operation and must account for every record and recovery reference.
class ManagedAttachmentFiles {
  ManagedAttachmentFiles(this.root, {this.syncDirectory});

  final Future<void> Function(Directory)? syncDirectory;

  final Directory root;
  static const _newOriginals = 'recording_originals';
  static const restoredOriginals = 'restored_originals';
  static final importIdPattern = RegExp(r'^[a-f0-9-]{36}$');

  Future<RecordingAttachment> copyOriginal(
    File source, {
    String? displayName,
    String? importId,
  }) async {
    final id = const Uuid().v4();
    final extension = p.extension(displayName ?? source.path);
    final suffix = RegExp(r'^\.[a-zA-Z0-9]{1,12}$').hasMatch(extension)
        ? extension
        : '';
    if (importId != null && !importIdPattern.hasMatch(importId)) {
      throw ArgumentError('Invalid restore attempt identity.');
    }
    final group = importId == null ? _newOriginals : restoredOriginals;
    final locator = [group, ?importId, '$id$suffix'].join('/');
    final name = displayName ?? p.basename(source.path);
    await root.create(recursive: true);
    final rootPath = await root.resolveSymbolicLinks();
    final parent = Directory(p.join(rootPath, group));
    await _ensureDirectory(parent);
    final directory = importId == null
        ? parent
        : Directory(p.join(parent.path, importId));
    await _ensureDirectory(directory);
    final pending = File(p.join(directory.path, '$id.part'));
    try {
      final file = await source.copy(pending.path);
      final writer = await file.open(mode: FileMode.append);
      try {
        await writer.flush();
      } finally {
        await writer.close();
      }
      final digest = await backupDigest(file);
      await file.rename(p.join(rootPath, locator));
      await syncDirectory?.call(directory);
      if (importId != null) await syncDirectory?.call(parent);
      await syncDirectory?.call(Directory(rootPath));
      return RecordingAttachment(
        id: id,
        kind: AttachmentKind.managed,
        locator: locator,
        name: name,
        originalFingerprint: digest,
      );
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  static Future<void> _ensureDirectory(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('The originals directory cannot be a link.');
    }
    await directory.create();
  }

  Future<File?> resolveOriginal(RecordingAttachment attachment) async {
    if (attachment.kind != AttachmentKind.managed || !await root.exists()) {
      return null;
    }
    final file = File(p.join(root.path, attachment.locator));
    if (!await file.exists()) return null;
    final resolved = await file.resolveSymbolicLinks();
    final directory = await root.resolveSymbolicLinks();
    return p.isWithin(directory, resolved) ? File(resolved) : null;
  }
}
