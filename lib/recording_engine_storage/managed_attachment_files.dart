import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../recording_engine/models.dart';

/// Stages originals independently of the database transaction. A failed save
/// leaves the staged original available for retry. Reclamation is a separate
/// operation and must account for every record and recovery reference.
class ManagedAttachmentFiles {
  ManagedAttachmentFiles(this.root);

  final Directory root;
  static const _newOriginals = 'recording_originals';

  Future<RecordingAttachment> copyOriginal(
    File source, {
    String? displayName,
  }) async {
    final id = const Uuid().v4();
    final extension = p.extension(displayName ?? source.path);
    final suffix = RegExp(r'^\.[a-zA-Z0-9]{1,12}$').hasMatch(extension)
        ? extension
        : '';
    final attachment = RecordingAttachment(
      id: id,
      kind: AttachmentKind.managed,
      locator: '$_newOriginals/$id$suffix',
      name: displayName ?? p.basename(source.path),
    );
    await root.create(recursive: true);
    final rootPath = await root.resolveSymbolicLinks();
    final directory = Directory(p.join(rootPath, _newOriginals));
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('The originals directory cannot be a link.');
    }
    await directory.create();
    final pending = File(p.join(directory.path, '$id.part'));
    try {
      final file = await source.copy(pending.path);
      final writer = await file.open(mode: FileMode.append);
      try {
        await writer.flush();
      } finally {
        await writer.close();
      }
      await file.rename(p.join(rootPath, attachment.locator));
      return attachment;
    } finally {
      if (await pending.exists()) await pending.delete();
    }
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
