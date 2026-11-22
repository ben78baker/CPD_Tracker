import 'dart:io';

import 'package:path/path.dart' as p;

/// A picker may return a provider's original or a private app cache copy.
/// Only the host can identify an owned copy, and it must prove containment.
class BackupInputFile {
  const BackupInputFile(this.file, {this.cacheRoot, this.nestedCache = false});

  final File file;
  final Directory? cacheRoot;
  final bool nestedCache;

  Future<void> dispose() async {
    final cache = cacheRoot;
    if (cache == null ||
        await FileSystemEntity.type(cache.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      return;
    }
    try {
      final root = await cache.resolveSymbolicLinks();
      final resolvedParent = await file.parent.resolveSymbolicLinks();
      final candidate = await file.resolveSymbolicLinks();
      if (!p.equals(candidate, p.join(resolvedParent, p.basename(file.path)))) {
        return;
      }
      if (!nestedCache) {
        if (!p.equals(resolvedParent, root)) return;
      } else if (!p.equals(p.dirname(resolvedParent), root) ||
          !RegExp(r'^[0-9]+$').hasMatch(p.basename(resolvedParent)) ||
          await FileSystemEntity.type(file.parent.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        return;
      }
      await file.delete();
    } on PathNotFoundException {
      // The provider or OS has already reclaimed the cache copy.
    }
  }
}

/// Use only for an app-owned staging directory at exclusive cold start.
Future<void> resetBackupScratch(Directory scratch) async {
  switch (await FileSystemEntity.type(scratch.path, followLinks: false)) {
    case FileSystemEntityType.notFound:
      break;
    case FileSystemEntityType.directory:
      await scratch.delete(recursive: true);
    default:
      throw FileSystemException('The backup staging path is not a directory.');
  }
  await scratch.create();
}
