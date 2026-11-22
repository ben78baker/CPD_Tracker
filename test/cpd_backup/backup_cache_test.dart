import 'dart:io';

import 'package:cpd_tracker/cpd_backup/backup_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'release deletes known private copies and preserves originals and aliases',
    () async {
      final root = await Directory.systemTemp.createTemp('backup_cache_test_');
      addTearDown(() => root.delete(recursive: true));
      final cache = await Directory(p.join(root.path, 'cache')).create();
      final picked = await Directory(p.join(cache.path, '12345')).create();
      final source = await File(
        p.join(root.path, 'backup'),
      ).writeAsString('outside');
      final copy = await source.copy(p.join(picked.path, 'backup'));
      final unexpected = await Directory(p.join(cache.path, 'other')).create();
      final other = await source.copy(p.join(unexpected.path, 'backup'));
      final alias = await Link(
        p.join(picked.path, 'alias'),
      ).create(source.path);
      final linkedParent = await Link(
        p.join(cache.path, '67890'),
      ).create(picked.path);
      await BackupInputFile(
        source,
        cacheRoot: cache,
        nestedCache: true,
      ).dispose();
      await BackupInputFile(
        other,
        cacheRoot: cache,
        nestedCache: true,
      ).dispose();
      await BackupInputFile(
        File(alias.path),
        cacheRoot: cache,
        nestedCache: true,
      ).dispose();
      await BackupInputFile(
        File(p.join(linkedParent.path, 'backup')),
        cacheRoot: cache,
        nestedCache: true,
      ).dispose();
      expect(await copy.exists(), isTrue);
      final owned = BackupInputFile(copy, cacheRoot: cache, nestedCache: true);
      await owned.dispose();
      await owned.dispose();

      expect(await copy.exists(), isFalse);
      expect(await alias.exists(), isTrue);
      expect(await source.readAsString(), 'outside');
      expect(await other.exists(), isTrue);
    },
  );

  test(
    'exclusive startup removes its own scratch, never a linked directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'backup_scratch_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final scratch = await Directory(p.join(root.path, 'scratch')).create();
      final nested = await Directory(p.join(scratch.path, 'review')).create();
      await File(
        p.join(nested.path, 'decrypted'),
      ).writeAsString('private scratch');
      final elsewhere = await Directory(p.join(root.path, 'outside')).create();
      final original = await File(
        p.join(elsewhere.path, 'original'),
      ).writeAsString('keep');
      final alias = await Link(
        p.join(root.path, 'alias'),
      ).create(elsewhere.path);

      await resetBackupScratch(scratch);
      expect(await scratch.list().isEmpty, isTrue);
      await expectLater(
        resetBackupScratch(Directory(alias.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await original.readAsString(), 'keep');
    },
  );
}
