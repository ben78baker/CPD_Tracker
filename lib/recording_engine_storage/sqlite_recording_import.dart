part of 'sqlite_recording_repository.dart';

Future<ImportSnapshot?> _loadImportSnapshot(
  DatabaseExecutor db,
  String sourceId,
) async {
  final rows = await db.query(
    'import_snapshots',
    columns: ['status', 'verified_at'],
    where: 'source_id = ?',
    whereArgs: [sourceId],
  );
  if (rows.isEmpty) return null;
  final row = rows.single;
  return ImportSnapshot(
    raw: (await _loadImportPayload(db, sourceId, 'raw'))!,
    status: ImportStatus.values.byName(row['status'] as String),
    metadata: await _loadImportPayload(db, sourceId, 'metadata'),
    verifiedAt: switch (row['verified_at']) {
      final String timestamp => DateTime.parse(timestamp),
      _ => null,
    },
  );
}

// Android's CursorWindow limits a single SQLite result row. Keep raw JSON and
// planner metadata off the marker row and bound each result independently.
const _importChunkBytes = 64 * 1024;

Future<String?> _loadImportPayload(
  DatabaseExecutor db,
  String sourceId,
  String kind,
) async {
  final rows = await db.query(
    'import_payload_chunks',
    columns: ['ordinal', 'content'],
    where: 'source_id = ? AND kind = ?',
    whereArgs: [sourceId, kind],
    orderBy: 'ordinal',
  );
  if (rows.isNotEmpty) {
    final bytes = BytesBuilder(copy: false);
    for (final (index, row) in rows.indexed) {
      if (row['ordinal'] != index) {
        throw StateError('A migration payload chunk is missing.');
      }
      bytes.add(row['content'] as Uint8List);
    }
    return utf8.decode(bytes.takeBytes());
  }
  // Phase 1 and 2 databases stored inline text. Read old SQLite TEXT by
  // characters so even an old oversized row can be recovered safely.
  final length =
      (await db.rawQuery(
            'SELECT length($kind) FROM import_snapshots WHERE source_id = ?',
            [sourceId],
          )).single.values.single
          as int?;
  if (length == null) return null;
  final result = StringBuffer();
  for (var offset = 0; offset < length; offset += _importChunkBytes) {
    final part = await db.rawQuery(
      'SELECT substr($kind, ?, ?) FROM import_snapshots WHERE source_id = ?',
      [offset + 1, _importChunkBytes, sourceId],
    );
    result.write(part.single.values.single as String);
  }
  return result.toString();
}

Future<void> _writeImportPayload(
  DatabaseExecutor db,
  String sourceId,
  String kind,
  String text,
) async {
  final bytes = utf8.encode(text);
  final batch = db.batch();
  batch.delete(
    'import_payload_chunks',
    where: 'source_id = ? AND kind = ?',
    whereArgs: [sourceId, kind],
  );
  for (
    var start = 0;
    start < bytes.length || start == 0;
    start += _importChunkBytes
  ) {
    final end = start + _importChunkBytes;
    batch.insert('import_payload_chunks', {
      'source_id': sourceId,
      'kind': kind,
      'ordinal': start ~/ _importChunkBytes,
      'content': Uint8List.sublistView(
        bytes,
        start,
        end < bytes.length ? end : bytes.length,
      ),
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _captureImport(
  DatabaseExecutor tx,
  String sourceId,
  String raw,
) async {
  if (sourceId.trim().isEmpty) {
    throw ArgumentError('A source ID is required.');
  }
  final snapshot = await _loadImportSnapshot(tx, sourceId);
  if (snapshot != null) {
    if (snapshot.raw != raw) {
      throw StateError('The source ID refers to a different snapshot.');
    }
    return;
  }
  await tx.insert('import_snapshots', {
    'source_id': sourceId,
    'raw': '',
    'status': ImportStatus.captured.name,
  });
  await _writeImportPayload(tx, sourceId, 'raw', raw);
}

Future<ImportStatus> _stageImport(
  DatabaseExecutor tx,
  RecordingImportPlan plan,
) async {
  final snapshot = await _matchingSnapshot(tx, plan);
  if (snapshot.status == ImportStatus.staged ||
      snapshot.status == ImportStatus.verified) {
    if (snapshot.metadata != plan.metadata || plan.blocked) {
      throw StateError('The staging plan differs from the recorded plan.');
    }
    await _verifyGraph(tx, plan);
    return snapshot.status;
  }
  if (plan.blocked) {
    await _setImportStatus(tx, plan, ImportStatus.blocked);
    return ImportStatus.blocked;
  }
  final staged = await tx.query(
    'import_snapshots',
    where: 'status IN (?, ?)',
    whereArgs: [ImportStatus.staged.name, ImportStatus.verified.name],
    limit: 1,
  );
  if (staged.isNotEmpty) {
    throw StateError('Use a fresh destination for a different source.');
  }
  for (final table in ['collections', 'templates', 'attachments']) {
    await _expectCount(tx, table, 0);
  }
  final layouts = {
    for (final layout in plan.layouts) layout.collectionId: layout,
  };
  if (layouts.length != plan.layouts.length ||
      layouts.length != plan.collections.length) {
    throw ArgumentError('An import needs one initial layout per collection.');
  }
  for (final collection in plan.collections) {
    final layout = layouts[collection.id];
    if (collection.layoutVersion != 1 ||
        layout == null ||
        layout.version != 1 ||
        layout.includeExisting.isNotEmpty ||
        layout.templateId != null) {
      throw ArgumentError('Invalid initial import layout.');
    }
    await SqliteRecordingRepository._insertCollection(tx, collection);
    await SqliteRecordingRepository._insertLayout(tx, layout);
  }
  const batchSize = 128;
  for (var start = 0; start < plan.attachments.length; start += batchSize) {
    final batch = tx.batch();
    for (final attachment in plan.attachments.skip(start).take(batchSize)) {
      batch.insert(
        'attachments',
        SqliteRecordingRepository._attachmentRow(attachment),
      );
    }
    await batch.commit(noResult: true);
  }
  for (var start = 0; start < plan.records.length; start += batchSize) {
    final batch = tx.batch();
    for (final record in plan.records.skip(start).take(batchSize)) {
      final layout = layouts[record.collectionId];
      if (layout == null || record.layoutVersion != 1 || record.version != 1) {
        throw ArgumentError('Invalid initial import record.');
      }
      SqliteRecordingRepository._validateChanges(layout.fields, record.values);
      batch.insert('records', SqliteRecordingRepository._recordRow(record));
      for (final field in layout.fields) {
        final value = record.values[field.id];
        if (value == null) continue;
        for (final (table, row) in SqliteRecordingRepository._valueRows(
          record.id,
          field,
          value,
        )) {
          batch.insert(table, row);
        }
      }
    }
    // All batches still participate in the same outer SQLite transaction.
    await batch.commit(noResult: true);
  }
  await _verifyGraph(tx, plan);
  await _setImportStatus(tx, plan, ImportStatus.staged);
  return ImportStatus.staged;
}

Future<ImportSnapshot> _matchingSnapshot(
  DatabaseExecutor db,
  RecordingImportPlan plan,
) async {
  final snapshot = await _loadImportSnapshot(db, plan.sourceId);
  if (snapshot == null || snapshot.raw != plan.rawSnapshot) {
    throw StateError('Capture the exact source snapshot first.');
  }
  return snapshot;
}

Future<void> _setImportStatus(
  DatabaseExecutor db,
  RecordingImportPlan plan,
  ImportStatus status,
) async {
  if (status != ImportStatus.verified) {
    await _writeImportPayload(db, plan.sourceId, 'metadata', plan.metadata);
  }
  await db.update(
    'import_snapshots',
    {
      'status': status.name,
      if (status != ImportStatus.verified) 'metadata': null,
      if (status == ImportStatus.verified)
        'verified_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'source_id = ?',
    whereArgs: [plan.sourceId],
  );
}

Future<void> _verifyImport(
  SqliteRecordingRepository repository,
  RecordingImportPlan plan,
  Future<bool> Function(RecordingAttachment) verifyManagedOriginal,
) async {
  final snapshot = await _matchingSnapshot(repository._connection, plan);
  if (plan.blocked ||
      snapshot.metadata != plan.metadata ||
      (snapshot.status != ImportStatus.staged &&
          snapshot.status != ImportStatus.verified)) {
    throw StateError('Only a matching staged import can be verified.');
  }
  // Filesystem I/O stays outside the SQLite transaction. The synthetic caller
  // owns the originals and keeps them unchanged during this verification.
  for (final attachment in plan.attachments) {
    if (attachment.kind == AttachmentKind.managed &&
        !await verifyManagedOriginal(attachment)) {
      throw StateError('A managed original failed verification.');
    }
  }
  await repository._transaction((tx) async {
    final current = await _matchingSnapshot(tx, plan);
    if (current.metadata != plan.metadata ||
        (current.status != ImportStatus.staged &&
            current.status != ImportStatus.verified)) {
      throw StateError('The staging state changed during verification.');
    }
    final constraints = await tx.rawQuery('PRAGMA foreign_key_check');
    final integrity = await tx.rawQuery('PRAGMA quick_check');
    if (constraints.isNotEmpty ||
        integrity.length != 1 ||
        integrity.single.values.single != 'ok') {
      throw StateError('SQLite integrity check failed.');
    }
    await _verifyGraph(tx, plan);
    if (current.status == ImportStatus.staged) {
      await _setImportStatus(tx, plan, ImportStatus.verified);
    }
  });
}

Future<void> _expectCount(
  DatabaseExecutor db,
  String table,
  int expected,
) async {
  final rows = await db.rawQuery('SELECT COUNT(*) FROM $table');
  if (rows.single.values.single != expected) {
    throw StateError('Unexpected number of rows in $table.');
  }
}

Future<void> _verifyGraph(DatabaseExecutor db, RecordingImportPlan plan) async {
  await _expectCount(db, 'collections', plan.collections.length);
  await _expectCount(db, 'layouts', plan.layouts.length);
  await _expectCount(db, 'records', plan.records.length);
  await _expectCount(db, 'attachments', plan.attachments.length);
  final definitions = <(String, int), FieldDefinition>{
    for (final layout in plan.layouts)
      for (final field in layout.fields)
        (field.definition.id, field.definition.version): field.definition,
  };
  await _expectCount(db, 'definitions', definitions.length);
  for (final entry in definitions.entries) {
    final rows = await db.query(
      'definitions',
      where: 'id = ? AND version = ?',
      whereArgs: [entry.key.$1, entry.key.$2],
    );
    if (rows.length != 1 ||
        rows.single['payload'] != jsonEncode(entry.value.toJson())) {
      throw StateError('A staged field definition differs from the plan.');
    }
  }
  for (final expected in plan.collections) {
    final rows = await db.query(
      'collections',
      where: 'id = ?',
      whereArgs: [expected.id],
    );
    if (rows.length != 1 ||
        rows.single['label'] != expected.label ||
        rows.single['layout_version'] != expected.layoutVersion ||
        rows.single['deleted'] != (expected.deleted ? 1 : 0)) {
      throw StateError('A staged collection differs from the plan.');
    }
  }
  for (final expected in plan.layouts) {
    final layouts = await SqliteRecordingRepository._layouts(
      db,
      expected.collectionId,
    );
    if (layouts.length != 1 ||
        layouts.single.version != expected.version ||
        layouts.single.templateId != expected.templateId ||
        layouts.single.templateVersion != expected.templateVersion ||
        layouts.single.includeExisting.isNotEmpty ||
        _encodeLayoutSettings(layouts.single) !=
            _encodeLayoutSettings(expected) ||
        _encodeFields(layouts.single.fields) !=
            _encodeFields(expected.fields)) {
      throw StateError('A staged layout differs from the plan.');
    }
  }
  var expectedLinks = 0;
  var expectedValues = 0;
  final attachmentFields = {
    for (final layout in plan.layouts)
      layout.collectionId: {
        for (final field in layout.fields)
          if (field.definition.kind == FieldKind.attachments) field.id,
      },
  };
  final storedRecords = {
    for (final row in await SqliteRecordingRepository._loadRecordSet(db))
      row.id: row,
  };
  for (final expected in plan.records) {
    for (final value in expected.values.entries) {
      if (attachmentFields[expected.collectionId]!.contains(value.key)) {
        expectedLinks += (value.value as List).length;
      } else {
        expectedValues++;
      }
    }
    final actual = storedRecords[expected.id];
    if (actual == null ||
        actual.collectionId != expected.collectionId ||
        actual.layoutVersion != expected.layoutVersion ||
        actual.version != expected.version ||
        actual.deleted != expected.deleted ||
        actual.values.length != expected.values.length ||
        expected.values.entries.any(
          (value) =>
              jsonEncode(actual.values[value.key]) != jsonEncode(value.value),
        )) {
      throw StateError('A staged record differs from the plan.');
    }
  }
  await _expectCount(db, 'attachment_links', expectedLinks);
  await _expectCount(db, 'record_values', expectedValues);
  final assetRows = {
    for (final row in await db.query('attachments')) row['id'] as String: row,
  };
  for (final expected in plan.attachments) {
    final row = assetRows[expected.id];
    if (row == null ||
        row['kind'] != expected.kind.name ||
        row['locator'] != expected.locator ||
        row['name'] != expected.name) {
      throw StateError('A staged attachment differs from the plan.');
    }
  }
}
