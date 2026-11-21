import 'dart:io';

import 'package:path/path.dart' as p;

/// Evidence-preserving copy for a cold recovery session. The caller owns the
/// exclusive startup path and must close every SQLite writer before copying.
/// This can preserve damaged files for inspection. It never publishes a
/// replacement live database, even if the copy is readable.
Future<Directory> copyQuiescentRecordingFiles({
  required File database,
  required File fence,
  required Directory destination,
  Iterable<Directory> originals = const [],
}) async {
  final parent = await destination.parent.resolveSymbolicLinks();
  final target = p.join(parent, p.basename(destination.path));
  final dbParent = await database.parent.resolveSymbolicLinks();
  final roots = <Directory, String>{};
  for (final root in originals) {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.directory) {
      throw StateError('An evidence root is unavailable.');
    }
    roots[root] = await root.resolveSymbolicLinks();
  }
  final protected = [dbParent, ...roots.values];
  if (protected.any(
    (root) =>
        p.equals(root, target) ||
        p.isWithin(root, target) ||
        p.isWithin(target, root),
  )) {
    throw ArgumentError('Use a separate recovery destination.');
  }
  final inputs = <String, File>{};
  for (final (name, file) in [
    ('authority.json', fence),
    for (final suffix in ['', '-wal', '-shm', '-journal'])
      ('recording.sqlite$suffix', File('${database.path}$suffix')),
  ]) {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file) {
      throw StateError('Unsafe recording artifact.');
    }
    inputs[name] = file;
  }
  if (inputs.isEmpty) {
    throw StateError('There are no recording files to preserve.');
  }

  for (final entry in roots.entries) {
    await for (final entity in entry.key.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Directory) continue;
      if (entity is! File) {
        throw StateError('An evidence item needs independent review.');
      }
      final relative = p.relative(entity.path, from: entry.key.path);
      final name = p.join('originals', p.basename(entry.key.path), relative);
      if (inputs.containsKey(name)) {
        throw StateError('Duplicate evidence location.');
      }
      inputs[name] = entity;
    }
  }

  Future<void> requireFresh() async {
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('The recovery destination already exists.');
    }
  }

  await requireFresh();
  final scratch = await Directory(parent).createTemp('.recording-preserve-');
  try {
    for (final input in inputs.entries) {
      final output = File(p.join(scratch.path, input.key));
      await output.parent.create(recursive: true);
      await input.value.copy(output.path);
      final handle = await output.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
    }
    for (final input in inputs.entries) {
      if (!await _sameBytes(
        input.value,
        File(p.join(scratch.path, input.key)),
      )) {
        throw StateError('A recording file changed during preservation.');
      }
    }
    await requireFresh();
    return await scratch.rename(target);
  } finally {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  }
}

Future<bool> _sameBytes(File source, File copy) async {
  final left = await source.open();
  try {
    final right = await copy.open();
    try {
      while (true) {
        final expected = await left.read(65536);
        final actual = await right.read(65536);
        if (expected.length != actual.length) return false;
        if (expected.isEmpty) return true;
        for (var index = 0; index < expected.length; index++) {
          if (expected[index] != actual[index]) return false;
        }
      }
    } finally {
      await right.close();
    }
  } finally {
    await left.close();
  }
}
