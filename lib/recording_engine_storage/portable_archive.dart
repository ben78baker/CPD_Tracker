import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef AvailableStorage = Future<int> Function(Directory directory);

enum BackupProblem {
  format,
  version,
  integrity,
  capacity,
  destination,
  authentication,
}

class BackupException implements Exception {
  const BackupException(this.problem, this.message);

  final BackupProblem problem;
  final String message;

  @override
  String toString() => 'Backup ${problem.name}: $message';
}

class BackupEntry {
  const BackupEntry(this.path, this.size, this.digest);

  final String path;
  final int size;
  final String digest;

  Map<String, Object> toJson() => {
    'path': path,
    'size': size,
    'sha256': digest,
  };
}

class BackupInspection {
  const BackupInspection._(
    this.created,
    this.schema,
    this.entries,
    this.seal,
    this.collection,
  );

  final DateTime created;
  final int schema;
  final List<BackupEntry> entries;
  final Map<String, dynamic>? collection;

  /// Binds a subsequent restore to exactly the manifest the user inspected.
  /// This is an integrity fingerprint, never a signature or an entitlement.
  final String seal;

  int get size => entries.fold(0, (sum, entry) => sum + entry.size);
  int get originals => entries.length - 1;
}

/// A flat, uncompressed stream. Names label payloads and never form an
/// arbitrary extraction tree. Every payload and the exact extent are checked.
class PortableArchive {
  const PortableArchive();

  static const _magic = 'RECBAK01';
  static const _version = 1;
  static const rows = 'rows.ndjson';
  static const _manifestLimit = 8 * 1024 * 1024;
  static const _entryLimit = 20000;
  static const _totalLimit = 64 * 1024 * 1024 * 1024;
  static final _entryPath = RegExp(r'^evidence/[a-zA-Z0-9_-]{1,100}$');
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  static final _publishing = <String>{};

  Future<BackupInspection> write({
    required Map<String, File> files,
    required File destination,
    required DateTime created,
    required int schema,
    required AvailableStorage available,
    Map<String, Object?>? collection,
    Map<String, String> expectedDigests = const {},
  }) async {
    final parent = await destination.parent.resolveSymbolicLinks();
    final target = p.join(parent, p.basename(destination.path));
    if (!_publishing.add(target)) {
      throw const BackupException(
        BackupProblem.destination,
        'A backup is being created here.',
      );
    }
    try {
      return await _write(
        files,
        File(target),
        created,
        schema,
        available,
        collection,
        expectedDigests,
      );
    } finally {
      _publishing.remove(target);
    }
  }

  Future<BackupInspection> _write(
    Map<String, File> files,
    File destination,
    DateTime created,
    int schema,
    AvailableStorage available,
    Map<String, Object?>? collection,
    Map<String, String> expectedDigests,
  ) async {
    _checkNames(files.keys);
    await _requireAbsent(destination);
    final entries = <BackupEntry>[];
    for (final input in files.entries) {
      if (await FileSystemEntity.type(input.value.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const BackupException(BackupProblem.integrity, 'Missing input.');
      }
      final size = await input.value.length();
      if (size > _totalLimit) _invalid();
      final digest = await backupDigest(input.value);
      if (expectedDigests[input.key] case final expected?
          when expected != digest) {
        throw const BackupException(
          BackupProblem.integrity,
          'Evidence changed during backup.',
        );
      }
      entries.add(BackupEntry(input.key, size, digest));
    }
    final manifest = utf8.encode(
      jsonEncode({
        'version': collection == null ? _version : 2,
        'collection': ?collection,
        'created': created.toUtc().toIso8601String(),
        'schema': schema,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      }),
    );
    final size = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    if (size > _totalLimit || manifest.length > _manifestLimit) _invalid();
    await requireBackupCapacity(
      destination.parent,
      manifest.length + 12 + size,
      available,
    );

    final staging = await destination.parent.createTemp('.backup-write-');
    try {
      final partial = File(p.join(staging.path, 'partial'));
      final writer = await partial.open(mode: FileMode.writeOnly);
      try {
        await writer.writeFrom(ascii.encode(_magic));
        await writer.writeFrom(
          (ByteData(4)..setUint32(0, manifest.length)).buffer.asUint8List(),
        );
        await writer.writeFrom(manifest);
        for (final entry in entries) {
          await for (final chunk in files[entry.path]!.openRead()) {
            await writer.writeFrom(chunk);
          }
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      final verified = await inspect(partial);
      await _requireAbsent(destination);
      await partial.rename(destination.path);
      return verified;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<BackupInspection> inspect(File source) => _read(source);

  /// Writes only into a fresh, private staging directory supplied by the caller.
  /// A failed read leaves the staged tree unfit for publication.
  Future<BackupInspection> extract(
    File source,
    Directory staging, {
    required AvailableStorage available,
    required String expectedSeal,
  }) => _read(
    source,
    staging: staging,
    expectedSeal: expectedSeal,
    available: available,
  );

  Future<BackupInspection> _read(
    File source, {
    Directory? staging,
    String? expectedSeal,
    AvailableStorage? available,
  }) async {
    final reader = await source.open();
    try {
      final magic = await reader.read(8);
      if (ascii.decode(magic, allowInvalid: true) != _magic) _invalid();
      final lengthBytes = await reader.read(4);
      if (lengthBytes.length != 4) _invalid();
      final length = ByteData.sublistView(lengthBytes).getUint32(0);
      if (length == 0 || length > _manifestLimit) _invalid();
      final bytes = await reader.read(length);
      if (bytes.length != length) _invalid();
      final manifest = _parse(bytes);
      if (expectedSeal != null && manifest.seal != expectedSeal) {
        throw const BackupException(
          BackupProblem.integrity,
          'Backup changed after review.',
        );
      }
      if (await reader.length() != 12 + length + manifest.size) {
        throw const BackupException(
          BackupProblem.integrity,
          'Incorrect file length.',
        );
      }
      if (staging != null) {
        if (await staging.list().isEmpty == false) {
          throw const BackupException(
            BackupProblem.destination,
            'Staging must be empty.',
          );
        }
        await requireBackupCapacity(staging, manifest.size, available!);
        await Directory(p.join(staging.path, 'evidence')).create();
      }
      for (final entry in manifest.entries) {
        final output = staging == null
            ? null
            : await File(
                p.joinAll([staging.path, ...entry.path.split('/')]),
              ).open(mode: FileMode.writeOnly);
        final digest = _DigestSink();
        final hasher = sha256.startChunkedConversion(digest);
        try {
          var remaining = entry.size;
          while (remaining > 0) {
            final chunk = await reader.read(
              remaining > 65536 ? 65536 : remaining,
            );
            if (chunk.isEmpty) _invalid();
            hasher.add(chunk);
            if (output != null) await output.writeFrom(chunk);
            remaining -= chunk.length;
          }
          hasher.close();
          if (digest.value.toString() != entry.digest) {
            throw const BackupException(
              BackupProblem.integrity,
              'Payload fingerprint mismatch.',
            );
          }
          if (output != null) await output.flush();
        } finally {
          await output?.close();
        }
      }
      if ((await reader.read(1)).isNotEmpty) _invalid();
      return manifest;
    } finally {
      await reader.close();
    }
  }

  BackupInspection _parse(List<int> bytes) {
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final scope = data['collection'];
      final version = data['version'];
      if (!((version == _version && scope == null) ||
          (version == 2 && scope is Map<String, dynamic>))) {
        throw const BackupException(
          BackupProblem.version,
          'Unsupported archive version.',
        );
      }
      final schema = data['schema'] as int;
      final created = DateTime.parse(data['created'] as String);
      final raw = data['entries'] as List;
      if (raw.length > _entryLimit || !created.isUtc || schema < 1) _invalid();
      final entries = <BackupEntry>[];
      var total = 0;
      for (final item in raw) {
        final entry = item as Map<String, dynamic>;
        final size = entry['size'] as int;
        final digest = entry['sha256'] as String;
        if (size < 0 || size > _totalLimit || !_digest.hasMatch(digest)) {
          _invalid();
        }
        total += size;
        if (total > _totalLimit) _invalid();
        entries.add(BackupEntry(entry['path'] as String, size, digest));
      }
      _checkNames(entries.map((entry) => entry.path));
      return BackupInspection._(
        created,
        schema,
        List.unmodifiable(entries),
        sha256.convert(bytes).toString(),
        scope == null ? null : Map<String, dynamic>.unmodifiable(scope as Map),
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      _invalid();
    }
  }

  void _checkNames(Iterable<String> names) {
    final unique = <String>{};
    if (names.isEmpty || names.first != rows || names.length > _entryLimit) {
      _invalid();
    }
    for (final name in names) {
      if (!unique.add(name.toLowerCase()) ||
          (name != rows && !_entryPath.hasMatch(name))) {
        _invalid();
      }
    }
  }

  Never _invalid() => throw const BackupException(
    BackupProblem.format,
    'Invalid backup structure.',
  );
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<String> backupDigest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> requireBackupCapacity(
  Directory directory,
  int bytes,
  AvailableStorage available,
) async {
  if (await available(directory) < bytes) {
    throw const BackupException(
      BackupProblem.capacity,
      'Insufficient storage.',
    );
  }
}

Future<void> _requireAbsent(FileSystemEntity entity) async {
  if (await FileSystemEntity.type(entity.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const BackupException(
      BackupProblem.destination,
      'Destination already exists.',
    );
  }
}
