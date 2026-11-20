import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../recording_engine/import_plan.dart';
import '../recording_engine/models.dart';

part 'sqlite_recording_import.dart';

/// The native driver closed the handle after SQLite ran out of writable
/// pages. Reopen the same path after capacity is available.
class RecordingStorageFull implements Exception {
  const RecordingStorageFull();
}

class SqliteRecordingRepository {
  SqliteRecordingRepository._(this._db);

  final DatabaseExecutor _db;
  static const _uuid = Uuid();

  /// An explicit database path is required. No application storage is opened
  /// unless a host deliberately constructs this adapter.
  static Future<SqliteRecordingRepository> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, from, to) async {
          if (from == 1) await db.execute(_hostStateSchema);
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          final result = await db.rawQuery('PRAGMA foreign_keys');
          if (result.single.values.single != 1) {
            throw StateError('SQLite foreign keys could not be enabled.');
          }
        },
        onCreate: (db, _) async {
          for (final sql in _schema) {
            await db.execute(sql);
          }
        },
      ),
    );
    return SqliteRecordingRepository._(db);
  }

  Database get _connection {
    final db = _db;
    if (db is Database) return db;
    throw StateError('This operation needs the owning repository.');
  }

  Future<void> close() => _connection.close();

  /// Apply host metadata and recording mutations in one SQL transaction.
  /// Use the scoped repository only inside the callback and let errors escape.
  Future<T> transaction<T>(
    Future<T> Function(SqliteRecordingRepository scoped) run,
  ) {
    if (_db is! Database) throw StateError('A transaction is already active.');
    return _transaction((tx) => run(SqliteRecordingRepository._(tx)));
  }

  Future<T> _transaction<T>(Future<T> Function(DatabaseExecutor) run) async {
    final db = _db;
    if (db is! Database) return run(db);
    var storageFull = false;
    try {
      return await db.transaction((tx) async {
        try {
          return await run(tx);
        } on DatabaseException catch (error) {
          storageFull = _isStorageFull(error);
          rethrow;
        }
      });
    } on DatabaseException catch (error) {
      if (!storageFull && !_isStorageFull(error)) rethrow;
      // SQLITE_FULL can automatically roll back. The plugin's subsequent
      // ROLLBACK may fail and leave its transaction ID active, so close the
      // handle before any attempt to read, write or retry on this connection.
      await db.close();
      throw const RecordingStorageFull();
    }
  }

  static bool _isStorageFull(DatabaseException error) =>
      ((error.getResultCode() ?? 0) & 0xff) == 13 ||
      error.toString().toLowerCase().contains('database or disk is full');

  Future<Map<String, String>> loadHostState(String namespace) async {
    final rows = await _db.query(
      'host_state',
      where: 'namespace = ?',
      whereArgs: [namespace],
    );
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> saveHostValue(String namespace, String key, String value) async {
    await _db.insert('host_state', {
      'namespace': namespace,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<RecordingCollection>> loadCollections() async {
    final rows = await _db.query('collections', orderBy: 'rowid');
    return rows.map(_decodeCollection).toList();
  }

  Future<void> updateCollection(
    String id, {
    String? label,
    bool? deleted,
  }) async {
    if (label != null && label.trim().isEmpty) {
      throw ArgumentError('A collection needs a label.');
    }
    if (label == null && deleted == null) return;
    final updated = await _db.update(
      'collections',
      {'label': ?label, if (deleted != null) 'deleted': deleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated != 1) throw StateError('Collection does not exist.');
  }

  static RecordingCollection _decodeCollection(Map<String, Object?> row) =>
      RecordingCollection(
        row['id'] as String,
        row['label'] as String,
        row['layout_version'] as int,
        deleted: row['deleted'] == 1,
      );

  Future<ImportSnapshot?> loadImportSnapshot(String sourceId) =>
      _loadImportSnapshot(_db, sourceId);

  Future<void> captureImport(String sourceId, String rawSnapshot) =>
      _transaction((tx) => _captureImport(tx, sourceId, rawSnapshot));

  Future<ImportStatus> stageImport(RecordingImportPlan plan) =>
      _transaction((tx) => _stageImport(tx, plan));

  Future<void> verifyImport(
    RecordingImportPlan plan, {
    required Future<bool> Function(RecordingAttachment) verifyManagedOriginal,
  }) => _verifyImport(this, plan, verifyManagedOriginal);

  Future<void> saveTemplate(TemplateVersion template) =>
      _transaction((tx) async {
        await _registerDefinitions(tx, template.fields);
        await tx.insert('templates', {
          'id': template.id,
          'version': template.version,
          'label': template.label,
          'fields': _encodeFields(template.fields),
        });
      });

  Future<TemplateVersion?> loadTemplate(String id, int version) async {
    final rows = await _db.query(
      'templates',
      where: 'id = ? AND version = ?',
      whereArgs: [id, version],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return TemplateVersion(
      id: id,
      version: version,
      label: row['label'] as String,
      fields: _decodeFields(row['fields'] as String),
    );
  }

  Future<RecordingCollection> createCollection(
    String label, {
    Iterable<LayoutField> fields = const [],
    int? maxActiveFields,
  }) => _transaction((tx) async {
    final collection = RecordingCollection(_uuid.v4(), label, 1);
    final layout = LayoutRevision(
      collectionId: collection.id,
      version: 1,
      fields: fields,
    );
    _validateFieldLimit(layout, maxActiveFields);
    await _insertCollection(tx, collection);
    await _insertLayout(tx, layout);
    return collection;
  });

  Future<RecordingCollection?> loadCollection(String id) async {
    final rows = await _db.query(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _decodeCollection(rows.single);
  }

  Future<LayoutRevision> applyTemplate(
    String collectionId,
    TemplateVersion template, {
    required int expectedVersion,
    int? maxActiveFields,
  }) async {
    final saved = await loadTemplate(template.id, template.version);
    if (saved == null ||
        saved.label != template.label ||
        _encodeFields(saved.fields) != _encodeFields(template.fields)) {
      throw StateError('Apply a saved, immutable template version.');
    }
    return _reviseLayout(
      collectionId,
      [
        for (final field in saved.fields)
          LayoutField(
            id: _uuid.v4(),
            definition: field.definition,
            labelOverride: field.labelOverride,
            required: field.required,
            helpText: field.helpText,
            placeholder: field.placeholder,
          ),
      ],
      expectedVersion: expectedVersion,
      maxActiveFields: maxActiveFields,
      templateId: saved.id,
      templateVersion: saved.version,
    );
  }

  Future<LayoutRevision> reviseLayout(
    String collectionId,
    Iterable<LayoutField> fields, {
    required int expectedVersion,
    Iterable<String> includeExisting = const [],
    int? maxActiveFields,
  }) => _reviseLayout(
    collectionId,
    fields,
    expectedVersion: expectedVersion,
    includeExisting: includeExisting,
    maxActiveFields: maxActiveFields,
  );

  Future<LayoutRevision> _reviseLayout(
    String collectionId,
    Iterable<LayoutField> fields, {
    required int expectedVersion,
    Iterable<String> includeExisting = const [],
    int? maxActiveFields,
    String? templateId,
    int? templateVersion,
  }) => _transaction((tx) async {
    final current = await _activeLayoutVersion(tx, collectionId);
    if (current != expectedVersion) throw StateError('The layout has changed.');
    final revisions = await _layouts(tx, collectionId);
    final historic = {
      for (final layout in revisions)
        for (final field in layout.fields) field.id: field,
    };
    final revision = LayoutRevision(
      collectionId: collectionId,
      version: current + 1,
      fields: fields,
      includeExisting: includeExisting,
      templateId: templateId ?? revisions.last.templateId,
      templateVersion: templateVersion ?? revisions.last.templateVersion,
    );
    _validateFieldLimit(revision, maxActiveFields);
    final previousIds = revisions.last.fields.map((field) => field.id).toSet();
    for (final field in revision.fields) {
      final previous = historic[field.id];
      if (previous != null &&
          (!previousIds.contains(field.id) ||
              revision.includeExisting.contains(field.id) ||
              previous.definition.kind != field.definition.kind ||
              previous.definition.id != field.definition.id ||
              previous.definition.version > field.definition.version)) {
        throw ArgumentError(
          'Use a new field ID for a replacement or historical addition.',
        );
      }
    }
    await _insertLayout(tx, revision);
    await tx.update(
      'collections',
      {'layout_version': revision.version},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
    return revision;
  });

  Future<List<LayoutRevision>> loadLayouts(String collectionId) =>
      _layouts(_db, collectionId);

  Future<void> saveAttachment(RecordingAttachment attachment) =>
      _transaction((tx) => _insertAttachment(tx, attachment));

  Future<RecordingAttachment?> loadAttachment(String id) async {
    final rows = await _db.query(
      'attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return RecordingAttachment(
      id: id,
      kind: AttachmentKind.values.byName(row['kind'] as String),
      locator: row['locator'] as String,
      name: row['name'] as String,
    );
  }

  Future<RecordingRecord> createRecord(
    String collectionId,
    Map<String, Object> values, {
    required int expectedLayoutVersion,
    Iterable<RecordingAttachment> newAttachments = const [],
  }) => _transaction((tx) async {
    final version = await _activeLayoutVersion(tx, collectionId);
    if (version != expectedLayoutVersion) {
      throw StateError('The layout has changed.');
    }
    final layout = (await _layouts(tx, collectionId)).last;
    final record = RecordingRecord(
      id: _uuid.v4(),
      collectionId: collectionId,
      layoutVersion: version,
      version: 1,
      deleted: false,
      values: values,
    );
    _validateChanges(layout.fields, record.values);
    for (final field in layout.fields.where((field) => field.required)) {
      if (!record.values.containsKey(field.id) ||
          record.values[field.id] == '') {
        throw ArgumentError('A required field is blank.');
      }
    }
    await _insertLinkedAttachments(
      tx,
      layout.fields,
      record.values,
      newAttachments,
    );
    await _insertRecord(tx, record, layout.fields);
    return record;
  });

  /// A patch preserves values and attachment links for fields it does not touch.
  /// Null clears a field; a historical required field can remain absent.
  Future<RecordingRecord> updateValues(
    String id,
    Map<String, Object?> changes, {
    required int expectedVersion,
    Iterable<RecordingAttachment> newAttachments = const [],
  }) => _transaction((tx) async {
    final record = await _requireRecord(tx, id, expectedVersion);
    if (record.deleted) {
      throw StateError('Restore the record before editing it.');
    }
    await _activeLayoutVersion(tx, record.collectionId);
    final fields = resolveFields(
      record.layoutVersion,
      await _layouts(tx, record.collectionId),
    );
    _validateChanges(fields, changes);
    await _insertLinkedAttachments(tx, fields, changes, newAttachments);
    final updated = Map<String, Object>.of(record.values);
    for (final change in changes.entries) {
      final field = fields.firstWhere(
        (candidate) => candidate.id == change.key,
      );
      if (field.required && (change.value == null || change.value == '')) {
        throw ArgumentError('A required field cannot be cleared.');
      }
      await _writeValue(tx, id, field, change.value);
      if (change.value case final value?) {
        updated[change.key] = value;
      } else {
        updated.remove(change.key);
      }
    }
    await tx.update(
      'records',
      {'edit_version': expectedVersion + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    return RecordingRecord(
      id: id,
      collectionId: record.collectionId,
      layoutVersion: record.layoutVersion,
      version: expectedVersion + 1,
      deleted: false,
      values: updated,
    );
  });

  Future<void> setRecordDeleted(
    String id,
    bool deleted, {
    required int expectedVersion,
  }) => _transaction((tx) async {
    final record = await _requireRecord(tx, id, expectedVersion);
    if (!deleted) await _activeLayoutVersion(tx, record.collectionId);
    if (record.deleted == deleted) return;
    await tx.update(
      'records',
      {'deleted': deleted ? 1 : 0, 'edit_version': expectedVersion + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  Future<RecordingRecord?> loadRecord(String id) =>
      _transaction((tx) => _loadRecord(tx, id));

  Future<List<RecordingRecord>> loadRecords(
    String collectionId, {
    bool includeDeleted = false,
  }) => _transaction((tx) async {
    final rows = await tx.query(
      'records',
      columns: ['id'],
      where: includeDeleted
          ? 'collection_id = ?'
          : 'collection_id = ? AND deleted = 0',
      whereArgs: [collectionId],
      orderBy: 'rowid',
    );
    return [
      for (final row in rows) (await _loadRecord(tx, row['id'] as String))!,
    ];
  });

  static Future<int> _activeLayoutVersion(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'collections',
      columns: ['layout_version'],
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('The collection is unavailable.');
    return rows.single['layout_version'] as int;
  }

  static Future<RecordingRecord> _requireRecord(
    DatabaseExecutor db,
    String id,
    int expectedVersion,
  ) async {
    final record = await _loadRecord(db, id);
    if (record == null || record.version != expectedVersion) {
      throw StateError('The record is missing or has changed.');
    }
    return record;
  }

  static Future<RecordingRecord?> _loadRecord(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query('records', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final values = await db.query(
      'record_values',
      where: 'record_id = ?',
      whereArgs: [id],
    );
    final links = await db.query(
      'attachment_links',
      where: 'record_id = ?',
      whereArgs: [id],
      orderBy: 'field_id, ordinal',
    );
    final result = <String, Object>{
      for (final value in values)
        value['field_id'] as String:
            jsonDecode(value['payload'] as String) as Object,
    };
    for (final link in links) {
      final fieldId = link['field_id'] as String;
      (result.putIfAbsent(fieldId, () => <String>[]) as List<String>).add(
        link['attachment_id'] as String,
      );
    }
    return RecordingRecord(
      id: id,
      collectionId: row['collection_id'] as String,
      layoutVersion: row['layout_version'] as int,
      version: row['edit_version'] as int,
      deleted: row['deleted'] == 1,
      values: result,
    );
  }

  static Future<List<LayoutRevision>> _layouts(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'layouts',
      where: 'collection_id = ?',
      whereArgs: [id],
      orderBy: 'version',
    );
    return [
      for (final row in rows)
        LayoutRevision(
          collectionId: id,
          version: row['version'] as int,
          fields: _decodeFields(row['fields'] as String),
          includeExisting:
              (jsonDecode(row['include_existing'] as String) as List)
                  .cast<String>(),
          templateId: row['template_id'] as String?,
          templateVersion: row['template_version'] as int?,
        ),
    ];
  }

  static void _validateChanges(
    List<LayoutField> fields,
    Map<String, Object?> values,
  ) {
    final byId = {for (final field in fields) field.id: field};
    for (final entry in values.entries) {
      final field = byId[entry.key];
      if (field == null) {
        throw ArgumentError('Field is not applicable to the record.');
      }
      if (entry.value case final value?) field.definition.validate(value);
    }
  }

  static Future<void> _insertCollection(
    DatabaseExecutor db,
    RecordingCollection collection,
  ) async {
    if (collection.label.trim().isEmpty) {
      throw ArgumentError('A collection needs a label.');
    }
    await db.insert('collections', {
      'id': collection.id,
      'label': collection.label,
      'layout_version': collection.layoutVersion,
      'deleted': collection.deleted ? 1 : 0,
    });
  }

  static Future<void> _insertLayout(
    DatabaseExecutor db,
    LayoutRevision revision,
  ) async {
    await _registerDefinitions(db, revision.fields);
    await db.insert('layouts', {
      'collection_id': revision.collectionId,
      'version': revision.version,
      'fields': _encodeFields(revision.fields),
      'include_existing': jsonEncode(revision.includeExisting.toList()),
      'template_id': revision.templateId,
      'template_version': revision.templateVersion,
    });
  }

  static Future<void> _registerDefinitions(
    DatabaseExecutor db,
    Iterable<LayoutField> fields,
  ) async {
    for (final field in fields) {
      final definition = field.definition;
      final payload = jsonEncode(definition.toJson());
      final rows = await db.query(
        'definitions',
        columns: ['payload'],
        where: 'id = ? AND version = ?',
        whereArgs: [definition.id, definition.version],
      );
      if (rows.isEmpty) {
        await db.insert('definitions', {
          'id': definition.id,
          'version': definition.version,
          'payload': payload,
        });
      } else if (rows.single['payload'] != payload) {
        throw StateError(
          'This field definition version already has other settings.',
        );
      }
    }
  }

  static void _validateFieldLimit(LayoutRevision layout, int? maximum) {
    if (maximum != null && layout.fields.length > maximum) {
      throw ArgumentError('The layout exceeds the active field limit.');
    }
  }

  static Future<void> _insertLinkedAttachments(
    DatabaseExecutor db,
    Iterable<LayoutField> fields,
    Map<String, Object?> values,
    Iterable<RecordingAttachment> additions,
  ) async {
    final linkedIds = {
      for (final field in fields)
        if (field.definition.kind == FieldKind.attachments)
          if (values[field.id] case final List ids) ...ids,
    };
    for (final attachment in additions) {
      if (!linkedIds.contains(attachment.id)) {
        throw ArgumentError('A new attachment must be linked to the record.');
      }
      await _insertAttachment(db, attachment);
    }
  }

  static Future<void> _insertAttachment(
    DatabaseExecutor db,
    RecordingAttachment attachment,
  ) async {
    await db.insert('attachments', {
      'id': attachment.id,
      'kind': attachment.kind.name,
      'locator': attachment.locator,
      'name': attachment.name,
    });
  }

  static Future<void> _insertRecord(
    DatabaseExecutor db,
    RecordingRecord record,
    List<LayoutField> fields,
  ) async {
    await db.insert('records', {
      'id': record.id,
      'collection_id': record.collectionId,
      'layout_version': record.layoutVersion,
      'edit_version': record.version,
      'deleted': record.deleted ? 1 : 0,
    });
    for (final field in fields) {
      if (record.values[field.id] case final value?) {
        await _writeValue(db, record.id, field, value);
      }
    }
  }

  static Future<void> _writeValue(
    DatabaseExecutor db,
    String id,
    LayoutField field,
    Object? value,
  ) async {
    final isAttachment = field.definition.kind == FieldKind.attachments;
    await db.delete(
      isAttachment ? 'attachment_links' : 'record_values',
      where: 'record_id = ? AND field_id = ?',
      whereArgs: [id, field.id],
    );
    if (value == null) return;
    if (isAttachment) {
      for (final (ordinal, asset) in (value as List).indexed) {
        await db.insert('attachment_links', {
          'record_id': id,
          'field_id': field.id,
          'ordinal': ordinal,
          'attachment_id': asset as String,
        });
      }
    } else {
      await db.insert('record_values', {
        'record_id': id,
        'field_id': field.id,
        'payload': jsonEncode(value),
      });
    }
  }
}

String _encodeFields(Iterable<LayoutField> fields) =>
    jsonEncode(fields.map((field) => field.toJson()).toList());

List<LayoutField> _decodeFields(String payload) => (jsonDecode(payload) as List)
    .cast<Map<String, dynamic>>()
    .map(LayoutField.fromJson)
    .toList();

const _hostStateSchema =
    'CREATE TABLE host_state ('
    'namespace TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, '
    'PRIMARY KEY(namespace, key))';

const _schema = [
  _hostStateSchema,
  '''CREATE TABLE import_snapshots (
    source_id TEXT NOT NULL PRIMARY KEY, raw TEXT NOT NULL,
    status TEXT NOT NULL, metadata TEXT, verified_at TEXT
  )''',
  '''CREATE TABLE definitions (
    id TEXT NOT NULL, version INTEGER NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY (id, version)
  )''',
  '''CREATE TABLE templates (
    id TEXT NOT NULL, version INTEGER NOT NULL, label TEXT NOT NULL,
    fields TEXT NOT NULL, PRIMARY KEY (id, version)
  )''',
  '''CREATE TABLE collections (
    id TEXT NOT NULL PRIMARY KEY, label TEXT NOT NULL,
    layout_version INTEGER NOT NULL, deleted INTEGER NOT NULL
  )''',
  '''CREATE TABLE layouts (
    collection_id TEXT NOT NULL REFERENCES collections(id),
    version INTEGER NOT NULL, fields TEXT NOT NULL, include_existing TEXT NOT NULL,
    template_id TEXT, template_version INTEGER,
    PRIMARY KEY (collection_id, version),
    FOREIGN KEY (template_id, template_version) REFERENCES templates(id, version)
  )''',
  '''CREATE TABLE records (
    id TEXT NOT NULL PRIMARY KEY, collection_id TEXT NOT NULL,
    layout_version INTEGER NOT NULL, edit_version INTEGER NOT NULL,
    deleted INTEGER NOT NULL,
    FOREIGN KEY (collection_id, layout_version) REFERENCES layouts(collection_id, version)
  )''',
  'CREATE INDEX records_collection_deleted ON records(collection_id, deleted)',
  '''CREATE TABLE record_values (
    record_id TEXT NOT NULL REFERENCES records(id), field_id TEXT NOT NULL,
    payload TEXT NOT NULL, PRIMARY KEY (record_id, field_id)
  )''',
  '''CREATE TABLE attachments (
    id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL,
    locator TEXT NOT NULL, name TEXT NOT NULL
  )''',
  '''CREATE TABLE attachment_links (
    record_id TEXT NOT NULL REFERENCES records(id), field_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL, attachment_id TEXT NOT NULL REFERENCES attachments(id),
    PRIMARY KEY (record_id, field_id, ordinal)
  )''',
  'CREATE INDEX attachment_links_asset ON attachment_links(attachment_id)',
];
