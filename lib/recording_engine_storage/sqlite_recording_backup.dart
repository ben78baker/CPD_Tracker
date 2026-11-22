part of 'sqlite_recording_repository.dart';

typedef PortableHostRow = bool Function(String namespace, String key);
typedef VerifyBackupHost =
    Future<void> Function(SqliteRecordingRepository repository);

/// Explicit workspace for a database and its originals. Restore publishes a
/// new, verified workspace. Authority is a separate host concern.
class RecordingWorkspace {
  const RecordingWorkspace(this.directory);

  final Directory directory;
  String get databasePath => p.join(directory.path, 'recording.sqlite');
  Directory get originals => Directory(p.join(directory.path, 'originals'));
}

class SqliteRecordingBackup {
  const SqliteRecordingBackup({
    required this.available,
    this.includeHostRow,
    this.verifyHost,
    this.factory,
  });

  final AvailableStorage available;
  final PortableHostRow? includeHostRow;
  final VerifyBackupHost? verifyHost;
  final DatabaseFactory? factory;
  static const _archive = PortableArchive();
  static const _lineLimit = 16 * 1024 * 1024;
  static const _temporaryReserve = 4 * 1024 * 1024;

  /// Keep the repository and original files under the same host write gate.
  /// Row export holds a SQL transaction and file names resolve under originals.
  Future<BackupInspection> create({
    required SqliteRecordingRepository repository,
    required Directory originals,
    required File destination,
    DateTime? created,
    Map<String, Object?>? collection,
    Map<String, String> evidenceDigests = const {},
  }) async {
    await requireBackupCapacity(
      destination.parent,
      _temporaryReserve,
      available,
    );
    final scratch = await destination.parent.createTemp('.backup-rows-');
    try {
      final data = File(p.join(scratch.path, PortableArchive.rows));
      final files = <String, File>{PortableArchive.rows: data};
      final fingerprints = <String, String>{};
      await repository.transaction((tx) async {
        await _verifyGraph(tx._db);
        await verifyHost?.call(tx);
        final writer = await data.open(mode: FileMode.writeOnly);
        final assets = <String, String>{};
        final caseFoldedPaths = <String>{};
        var rowBudget = 0;
        try {
          for (final table in _backupTables) {
            await for (final row in _pages(tx._db, table)) {
              _validateRow(table, row);
              if (!_include(table, row)) continue;
              String? entry;
              if (table == 'attachments') {
                final attachment = _decodeBackupAttachment(row);
                if (attachment.kind == AttachmentKind.managed) {
                  entry = assets[attachment.locator];
                  if (entry == null) {
                    if (!caseFoldedPaths.add(
                      attachment.locator.toLowerCase(),
                    )) {
                      _badRows();
                    }
                    entry = 'evidence/${assets.length}';
                    files[entry] = await _strictOriginal(
                      originals,
                      attachment.locator,
                    );
                    assets[attachment.locator] = entry;
                    if (evidenceDigests[attachment.locator]
                        case final digest?) {
                      fingerprints[entry] = digest;
                    }
                  }
                }
              }
              final bytes = utf8.encode(
                '${jsonEncode([
                  table,
                  row.map((key, value) => MapEntry(key, value is Uint8List ? {'blob': base64Encode(value)} : value)),
                  ?entry,
                ])}\n',
              );
              if (bytes.length > _lineLimit) {
                throw const BackupException(
                  BackupProblem.capacity,
                  'A data row exceeds the format limit.',
                );
              }
              if (rowBudget < bytes.length) {
                rowBudget = bytes.length + _temporaryReserve;
                await requireBackupCapacity(scratch, rowBudget, available);
              }
              await writer.writeFrom(bytes);
              rowBudget -= bytes.length;
            }
          }
          await writer.flush();
        } finally {
          await writer.close();
        }
      });
      return await _archive.write(
        files: files,
        destination: destination,
        created: created ?? DateTime.now(),
        schema: SqliteRecordingRepository.schemaVersion,
        available: available,
        collection: collection,
        expectedDigests: fingerprints,
      );
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  Future<BackupInspection> inspect(File source) async {
    final inspection = await _archive.inspect(source);
    _requireSchema(inspection);
    _requireScope(inspection, collection: false);
    return inspection;
  }

  /// Rebuild from trusted schema and bound parameters. Never open a raw
  /// external SQLite database or run SQL delivered in the file.
  Future<RecordingWorkspace> restore({
    required File source,
    required BackupInspection inspection,
    required Directory destination,
  }) => _restore(source, inspection, destination, collection: false);

  Future<RecordingWorkspace> _restore(
    File source,
    BackupInspection inspection,
    Directory destination, {
    required bool collection,
  }) async {
    _requireSchema(inspection);
    _requireScope(inspection, collection: collection);
    await _fresh(directory: destination);
    final rowBytes = inspection.entries.first.size;
    // Extraction, a second copy of evidence, database and rollback headroom.
    await requireBackupCapacity(
      destination.parent,
      2 * inspection.size + 4 * rowBytes + _temporaryReserve,
      available,
    );
    final scratch = await destination.parent.createTemp('.backup-restore-');
    try {
      final payload = await Directory(p.join(scratch.path, 'payload')).create();
      final verified = await _archive.extract(
        source,
        payload,
        available: available,
        expectedSeal: inspection.seal,
      );
      _requireSchema(verified);

      final staged = RecordingWorkspace(
        await Directory(p.join(scratch.path, 'store')).create(),
      );
      await staged.originals.create();
      final repo = await SqliteRecordingRepository.open(
        staged.databasePath,
        factory: factory,
      );
      try {
        await repo.transaction((tx) async {
          await _restoreRows(tx, payload, verified, staged.originals);
          await _verifyGraph(tx._db);
          await verifyHost?.call(tx);
        });
      } finally {
        await repo.close();
      }
      await _fresh(directory: destination);
      await staged.directory.rename(destination.path);
      return RecordingWorkspace(destination);
    } on FormatException {
      _badRows();
    } on ArgumentError {
      _badRows();
    } on TypeError {
      _badRows();
    } on DatabaseException {
      _badRows();
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  Future<void> _restoreRows(
    SqliteRecordingRepository tx,
    Directory payload,
    BackupInspection inspection,
    Directory originals,
  ) async {
    final evidence = {
      for (final entry in inspection.entries.skip(1)) entry.path: entry,
    };
    final used = <String, String>{};
    final locators = <String, String>{};
    final data = File(p.join(payload.path, PortableArchive.rows));
    var lastTable = 0;
    await for (final line in _boundedLines(data)) {
      final decoded = jsonDecode(utf8.decode(line)) as List;
      if (decoded.length < 2 || decoded.length > 3) _badRows();
      final table = decoded[0] as String;
      final position = _backupTables.indexOf(table);
      if (position < lastTable) _badRows();
      lastTable = position;
      final row = (decoded[1] as Map<String, dynamic>).map<String, Object?>(
        (key, value) => MapEntry(
          key,
          value is Map && value.length == 1
              ? base64Decode(value['blob'] as String)
              : value as Object?,
        ),
      );
      _validateRow(table, row);
      if (table == 'attachments') {
        final attachment = _decodeBackupAttachment(row);
        if (attachment.kind == AttachmentKind.managed) {
          if (decoded.length != 3) _badRows();
          final name = decoded[2] as String;
          final entry = evidence[name];
          final path = attachment.locator;
          if (entry == null ||
              (used[name] ?? path) != path ||
              (locators[path.toLowerCase()] ?? name) != name) {
            _badRows();
          }
          if (used[name] == null) {
            final file = File(p.joinAll([originals.path, ...path.split('/')]));
            await file.parent.create(recursive: true);
            if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              _badRows();
            }
            await File(p.join(payload.path, name)).copy(file.path);
            final handle = await file.open(mode: FileMode.append);
            try {
              await handle.flush();
            } finally {
              await handle.close();
            }
            if (await backupDigest(file) != entry.digest) _badRows();
            used[name] = path;
            locators[path.toLowerCase()] = name;
          }
        } else if (decoded.length != 2) {
          _badRows();
        }
      } else if (decoded.length != 2) {
        _badRows();
      }
      if (_include(table, row)) {
        // The default ABORT conflict action rejects duplicate identities.
        await tx._db.insert(table, row);
      }
    }
    if (used.length != evidence.length) _badRows();
  }

  static Future<void> _verifyGraph(DatabaseExecutor db) async {
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty ||
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single !=
            'ok' ||
        (await db.rawQuery(
          'SELECT 1 FROM collections c WHERE NOT EXISTS '
          '(SELECT 1 FROM layouts l WHERE l.collection_id = c.id AND '
          'l.version = c.layout_version) LIMIT 1',
        )).isNotEmpty) {
      _badRows();
    }
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final liveTables = tables
        .map((row) => row['name'] as String)
        .where(
          (name) => !name.startsWith('sqlite_') && name != 'android_metadata',
        )
        .toSet();
    if (liveTables.length != _backupTables.length ||
        !liveTables.containsAll(_backupTables)) {
      _badRows();
    }

    final definitions = <(String, int), String>{};
    await for (final row in _pages(db, 'definitions')) {
      final field = FieldDefinition.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      if (field.id != row['id'] || field.version != row['version']) _badRows();
      definitions[(field.id, field.version)] = jsonEncode(field.toJson());
    }
    void checkDefinition(LayoutField field) {
      final definition = field.definition;
      if (definitions[(definition.id, definition.version)] !=
          jsonEncode(definition.toJson())) {
        _badRows();
      }
    }

    final repository = SqliteRecordingRepository._(db);
    await for (final row in _pages(db, 'templates')) {
      final template = await repository.loadTemplate(
        row['id'] as String,
        row['version'] as int,
      );
      for (final field in template!.fields) {
        checkDefinition(field);
      }
    }
    // A field can be retired or introduced retrospectively. Check against
    // the collection's immutable history, rather than the current layout.
    await for (final collection in _pages(db, 'collections')) {
      final id = collection['id'] as String;
      final layouts = await SqliteRecordingRepository._layouts(db, id);
      final fieldsById = <String, List<LayoutField>>{};
      for (final layout in layouts) {
        for (final field in layout.fields) {
          checkDefinition(field);
          fieldsById.putIfAbsent(field.id, () => []).add(field);
        }
      }
      for (final table in ['record_values', 'attachment_links']) {
        await for (final row in _pages(db, table, collection: id)) {
          final fields = fieldsById[row['field_id']] ?? [];
          if (table == 'attachment_links') {
            if (!fields.any(
              (f) => f.definition.kind == FieldKind.attachments,
            )) {
              _badRows();
            }
          } else {
            final value = jsonDecode(row['payload'] as String);
            if (!fields.any((f) => _acceptsBackupValue(f, value))) _badRows();
          }
        }
      }
    }
    if ((await db.rawQuery(
      'SELECT 1 FROM record_values v JOIN attachment_links a '
      'ON a.record_id = v.record_id AND a.field_id = v.field_id LIMIT 1',
    )).isNotEmpty) {
      _badRows();
    }
  }

  bool _include(String table, Map<String, Object?> row) =>
      table != 'host_state' ||
      (includeHostRow?.call(row['namespace'] as String, row['key'] as String) ??
          true);

  static void _requireScope(
    BackupInspection inspection, {
    required bool collection,
  }) {
    if ((inspection.collection != null) != collection) {
      throw const BackupException(
        BackupProblem.version,
        'Incompatible backup scope.',
      );
    }
  }

  static void _requireSchema(BackupInspection inspection) {
    if (inspection.schema != SqliteRecordingRepository.schemaVersion) {
      throw const BackupException(
        BackupProblem.version,
        'Unsupported recording schema.',
      );
    }
  }
}

const _backupColumns = {
  'host_state': 'namespace:s,key:s,value:s',
  'import_snapshots': 'source_id:s,raw:s,status:s,metadata:n,verified_at:n',
  'import_payload_chunks': 'source_id:s,kind:s,ordinal:i,content:b',
  'definitions': 'id:s,version:i,payload:s',
  'templates': 'id:s,version:i,label:s,fields:s,settings:s',
  'collections': 'id:s,label:s,layout_version:i,deleted:i',
  'layouts':
      'collection_id:s,version:i,fields:s,include_existing:s,template_id:n,template_version:q,settings:s',
  'records': 'id:s,collection_id:s,layout_version:i,edit_version:i,deleted:i',
  'record_values': 'record_id:s,field_id:s,payload:s',
  'attachments': 'id:s,kind:s,locator:s,name:s',
  'attachment_links': 'record_id:s,field_id:s,ordinal:i,attachment_id:s',
};
final _backupTables = _backupColumns.keys.toList(growable: false);
final _backupTypes = _backupColumns.map(
  (table, columns) => MapEntry(table, {
    for (final c in columns.split(',')) c.split(':')[0]: c.split(':')[1],
  }),
);

void _validateRow(String table, Map<String, Object?> row) {
  final columns = _backupTypes[table];
  if (columns == null || columns.length != row.length) _badRows();
  for (final entry in row.entries) {
    final value = entry.value;
    final matches = switch (columns[entry.key]) {
      's' => value is String,
      'i' => value is int && value >= 0,
      'n' => value == null || value is String,
      'q' => value == null || value is int && value >= 1,
      'b' => value is Uint8List,
      _ => false,
    };
    if (!matches || entry.key == 'deleted' && value != 0 && value != 1) {
      _badRows();
    }
  }
  if (table == 'layouts' &&
      (row['template_id'] == null) != (row['template_version'] == null)) {
    _badRows();
  }
}

bool _acceptsBackupValue(LayoutField field, Object? value) {
  if (value == null || field.definition.kind == FieldKind.attachments) {
    return false;
  }
  try {
    field.definition.validate(value);
    return true;
  } on ArgumentError {
    return false;
  }
}

Stream<Map<String, Object?>> _pages(
  DatabaseExecutor db,
  String table, {
  String? collection,
}) async* {
  var cursor = 0;
  while (true) {
    final rows = await db.rawQuery(
      'SELECT t.rowid AS backup_rowid, t.* FROM $table t '
      '${collection == null ? '' : 'JOIN records r ON r.id = t.record_id '}'
      'WHERE t.rowid > ? ${collection == null ? '' : 'AND r.collection_id = ? '}'
      'ORDER BY t.rowid LIMIT 32',
      [cursor, ?collection],
    );
    if (rows.isEmpty) return;
    for (final row in rows) {
      cursor = row['backup_rowid'] as int;
      yield Map.of(row)..remove('backup_rowid');
    }
  }
}

Stream<List<int>> _boundedLines(File source) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final bytes in source.openRead()) {
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 10) continue;
      if (buffer.length + i - start >= SqliteRecordingBackup._lineLimit) {
        _badRows();
      }
      buffer.add(bytes.sublist(start, i));
      yield buffer.takeBytes();
      start = i + 1;
    }
    if (buffer.length + bytes.length - start >=
        SqliteRecordingBackup._lineLimit) {
      _badRows();
    }
    buffer.add(bytes.sublist(start));
  }
  if (buffer.isNotEmpty) _badRows();
}

RecordingAttachment _decodeBackupAttachment(Map<String, Object?> row) {
  final attachment = RecordingAttachment(
    id: row['id'] as String,
    kind: AttachmentKind.values.byName(row['kind'] as String),
    locator: row['locator'] as String,
    name: row['name'] as String,
  );
  if (attachment.kind == AttachmentKind.managed &&
      (attachment.locator.split('/').length > 16 ||
          utf8.encode(attachment.locator).length > 4096)) {
    _badRows();
  }
  if (attachment.kind == AttachmentKind.link) {
    final uri = Uri.tryParse(attachment.locator.trim());
    if (uri == null ||
        !(const ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty ||
            const ['mailto', 'tel'].contains(uri.scheme) &&
                uri.path.isNotEmpty)) {
      _badRows();
    }
  }
  return attachment;
}

Future<File> _strictOriginal(Directory root, String relative) async {
  if (await FileSystemEntity.type(root.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    _badRows();
  }
  final parent = await root.resolveSymbolicLinks();
  final file = File(p.joinAll([parent, ...relative.split('/')]));
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      !p.equals(await file.resolveSymbolicLinks(), file.path)) {
    _badRows();
  }
  return file;
}

Future<void> _fresh({required Directory directory}) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const BackupException(
      BackupProblem.destination,
      'Use a new restore workspace.',
    );
  }
}

Never _badRows() => throw const BackupException(
  BackupProblem.integrity,
  'Recording data or original evidence did not verify.',
);
