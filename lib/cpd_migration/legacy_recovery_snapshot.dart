import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'legacy_migration.dart';

/// Available bytes in the destination filesystem, supplied by the host.
typedef AvailableStorage = Future<int> Function(Directory destinationParent);

class InsufficientRecoveryStorage implements Exception {
  const InsufficientRecoveryStorage(this.requiredBytes, this.availableBytes);

  final int requiredBytes;
  final int availableBytes;
}

class RestoredLegacySource {
  const RestoredLegacySource(this.values, this.previousDocumentsPath);

  final Map<String, Object?> values;
  final String previousDocumentsPath;
}

/// Private recovery copy for a frozen synthetic source. The raw manifest and
/// owned files are independent of the staging database. A temporary directory
/// is verified before one rename publishes it.
class LegacyRecoverySnapshot {
  const LegacyRecoverySnapshot(this.directory);

  final Directory directory;

  static Future<LegacyRecoverySnapshot> capture({
    required Map<String, Object?> legacyValues,
    required Directory documents,
    required Directory destination,
    required AvailableStorage availableBytes,
  }) async {
    final parent = destination.parent;
    final sourceRoot = await documents.resolveSymbolicLinks();
    final targetRoot = await parent.resolveSymbolicLinks();
    if (p.equals(sourceRoot, targetRoot) ||
        p.isWithin(sourceRoot, targetRoot)) {
      throw ArgumentError(
        'Place the recovery copy outside the source Documents directory.',
      );
    }
    await _requireAbsent(destination);
    final raw = encodeLegacySnapshot(legacyValues);
    final inventory = await _inventory(sourceRoot);
    final size = _estimatedBytes(raw, inventory);
    final files = inventory.files;
    final excluded = inventory.excluded;
    final free = await availableBytes(parent);
    if (free < size) throw InsufficientRecoveryStorage(size, free);

    final staging = await parent.createTemp('.cpd-recovery-');
    try {
      final digests = <String, String>{};
      for (final file in files.entries) {
        final copy = File(p.join(staging.path, file.key));
        await copy.parent.create(recursive: true);
        final expected = await legacyFileFingerprint(file.value);
        await _copyFlushed(file.value, copy);
        if (await legacyFileFingerprint(copy) != expected) {
          throw StateError('An original changed during recovery capture.');
        }
        digests[file.key] = expected;
      }
      final snapshot = LegacyRecoverySnapshot(staging);
      await snapshot._manifest.writeAsString(
        jsonEncode({
          'version': 1,
          'sourceId': SyntheticCpdMigration.sourceIdentity(legacyValues),
          'raw': raw,
          'previousDocumentsPath': p.absolute(documents.path),
          'originals': digests,
          'excluded': excluded..sort(),
        }),
        flush: true,
      );
      await snapshot._manifestFingerprint.writeAsString(
        await legacyFileFingerprint(snapshot._manifest),
        flush: true,
      );
      await snapshot._readVerified();
      await _requireAbsent(destination);
      return LegacyRecoverySnapshot(await staging.rename(destination.path));
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static Future<int> estimateBytes(
    Map<String, Object?> values,
    Directory documents,
  ) async => _estimatedBytes(
    encodeLegacySnapshot(values),
    await _inventory(await documents.resolveSymbolicLinks()),
  );

  /// Recover raw values independently of evidence that may have been damaged.
  Future<RestoredLegacySource> readVerifiedSource() async {
    final snapshot = await _readVerified(checkOriginals: false);
    return RestoredLegacySource(
      snapshot.values,
      snapshot.previousDocumentsPath,
    );
  }

  /// Compare the separately stored originals against the frozen source tree.
  /// Used on resume and just before any authority marker is published.
  Future<String> verifyAgainstSource(
    Map<String, Object?> values,
    Directory documents,
  ) async {
    final snapshot = await _readVerified();
    if (encodeLegacySnapshot(snapshot.values) != encodeLegacySnapshot(values)) {
      throw StateError('Source preferences changed since recovery capture.');
    }
    final inventory = await _inventory(await documents.resolveSymbolicLinks());
    if (inventory.files.length != snapshot.originals.length ||
        jsonEncode(inventory.excluded) != jsonEncode(snapshot.excluded)) {
      throw StateError('The source evidence inventory changed.');
    }
    for (final original in snapshot.originals.entries) {
      final source = inventory.files[original.key];
      if (source == null ||
          await legacyFileFingerprint(source) != original.value) {
        throw StateError('An original changed since recovery capture.');
      }
    }
    return _manifestFingerprint.readAsString();
  }

  /// Cheap startup probe. Full evidence verification remains a recovery step.
  Future<String> verifyManifest() async {
    await _readVerified(checkOriginals: false);
    return _manifestFingerprint.readAsString();
  }

  Future<String> verify() async {
    await _readVerified();
    return _manifestFingerprint.readAsString();
  }

  /// Verify the complete copy first, then materialise a new scratch Documents
  /// directory. Never overwrite an existing source or destination.
  Future<RestoredLegacySource> restoreTo(Directory destination) async {
    await _requireAbsent(destination);
    final snapshot = await _readVerified();
    final parent = destination.parent;
    final sourceRoot = await directory.resolveSymbolicLinks();
    final targetRoot = await parent.resolveSymbolicLinks();
    if (p.equals(sourceRoot, targetRoot) ||
        p.isWithin(sourceRoot, targetRoot)) {
      throw ArgumentError('Use a destination outside the recovery copy.');
    }
    final staging = await parent.createTemp('.cpd-restore-');
    try {
      for (final entry in snapshot.originals.entries) {
        final source = File(p.join(directory.path, entry.key));
        final output = File(p.join(staging.path, entry.key));
        await output.parent.create(recursive: true);
        await _copyFlushed(source, output);
        if (await legacyFileFingerprint(output) != entry.value) {
          throw StateError('A recovery original changed during restore.');
        }
      }
      await _requireAbsent(destination);
      await staging.rename(destination.path);
      return RestoredLegacySource(
        snapshot.values,
        snapshot.previousDocumentsPath,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<List<String>> excludedPaths() async =>
      (await _readVerified(checkOriginals: false)).excluded;

  File get _manifest => File(p.join(directory.path, 'manifest.json'));
  File get _manifestFingerprint =>
      File(p.join(directory.path, 'manifest.fingerprint'));

  Future<
    ({
      Map<String, Object?> values,
      String previousDocumentsPath,
      Map<String, String> originals,
      List<String> excluded,
    })
  >
  _readVerified({bool checkOriginals = true}) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(_manifest.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('The recovery directory or manifest is unavailable.');
    }
    if (await FileSystemEntity.type(
              _manifestFingerprint.path,
              followLinks: false,
            ) !=
            FileSystemEntityType.file ||
        await _manifestFingerprint.readAsString() !=
            await legacyFileFingerprint(_manifest)) {
      throw StateError('The recovery manifest failed integrity verification.');
    }
    final manifest = jsonDecode(await _manifest.readAsString()) as Map;
    if (manifest['version'] != 1) {
      throw StateError('Unsupported recovery version.');
    }
    final previousDocumentsPath = manifest['previousDocumentsPath'] as String;
    if (!p.isAbsolute(previousDocumentsPath)) {
      throw StateError('Invalid source Documents location.');
    }
    final raw = manifest['raw'] as String;
    final values = (jsonDecode(raw) as Map).cast<String, Object?>();
    if (SyntheticCpdMigration.sourceIdentity(values) != manifest['sourceId'] ||
        encodeLegacySnapshot(values) != raw) {
      throw StateError(
        'The raw recovery snapshot failed integrity verification.',
      );
    }
    final root = await directory.resolveSymbolicLinks();
    final originals = (manifest['originals'] as Map).cast<String, String>();
    for (final entry in originals.entries) {
      if (!_safeLocator(entry.key)) {
        throw StateError('Unsafe recovery original path.');
      }
      if (!checkOriginals) continue;
      final path = p.join(root, entry.key);
      final file = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.resolveSymbolicLinks() != path ||
          await legacyFileFingerprint(file) != entry.value) {
        throw StateError('A recovery original failed integrity verification.');
      }
    }
    return (
      values: values,
      previousDocumentsPath: previousDocumentsPath,
      originals: originals,
      excluded: (manifest['excluded'] as List).cast<String>(),
    );
  }
}

Future<({Map<String, File> files, List<String> excluded, int bytes})>
_inventory(String sourceRoot) async {
  final evidence = Directory(p.join(sourceRoot, 'attachments'));
  final files = <String, File>{};
  final excluded = <String>[];
  var bytes = 0;
  final type = await FileSystemEntity.type(evidence.path, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await for (final item in evidence.list(
      recursive: true,
      followLinks: false,
    )) {
      final locator = p.relative(item.path, from: sourceRoot);
      if (item is File && _safeLocator(locator)) {
        files[locator] = item;
        bytes += await item.length() + utf8.encode(locator).length * 2 + 256;
      } else if (item is! Directory) {
        excluded.add(locator);
      }
    }
  } else if (type != FileSystemEntityType.notFound) {
    excluded.add('attachments');
  }
  return (files: files, excluded: excluded..sort(), bytes: bytes);
}

int _estimatedBytes(
  String raw,
  ({Map<String, File> files, List<String> excluded, int bytes}) inventory,
) => utf8.encode(raw).length * 2 + 1024 * 1024 + inventory.bytes;

bool _safeLocator(String locator) =>
    locator.startsWith('attachments/') &&
    !locator.contains(RegExp(r'[\\:\x00]')) &&
    !locator
        .split('/')
        .any((part) => part.isEmpty || part == '.' || part == '..');

Future<void> _requireAbsent(Directory destination) async {
  if (await FileSystemEntity.type(destination.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('The recovery destination already exists.');
  }
}

Future<void> _copyFlushed(File source, File destination) async {
  final copy = await source.copy(destination.path);
  final writer = await copy.open(mode: FileMode.append);
  try {
    await writer.flush();
  } finally {
    await writer.close();
  }
}
