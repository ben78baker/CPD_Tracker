part of 'sqlite_recording_repository.dart';

Future<ImportSnapshot?> _loadImportSnapshot(
  DatabaseExecutor db,
  String sourceId,
) async {
  final rows = await db.query(
    'import_snapshots',
    where: 'source_id = ?',
    whereArgs: [sourceId],
  );
  if (rows.isEmpty) return null;
  final row = rows.single;
  return ImportSnapshot(
    raw: row['raw'] as String,
    status: ImportStatus.values.byName(row['status'] as String),
    metadata: row['metadata'] as String?,
    verifiedAt: switch (row['verified_at']) {
      final String timestamp => DateTime.parse(timestamp),
      _ => null,
    },
  );
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
    'raw': raw,
    'status': ImportStatus.captured.name,
  });
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
  for (final attachment in plan.attachments) {
    await SqliteRecordingRepository._insertAttachment(tx, attachment);
  }
  for (final record in plan.records) {
    final layout = layouts[record.collectionId];
    if (layout == null || record.layoutVersion != 1 || record.version != 1) {
      throw ArgumentError('Invalid initial import record.');
    }
    SqliteRecordingRepository._validateChanges(layout.fields, record.values);
    // Legacy blanks can be imported even if a field is required for new input.
    await SqliteRecordingRepository._insertRecord(tx, record, layout.fields);
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
  await db.update(
    'import_snapshots',
    {
      'status': status.name,
      'metadata': plan.metadata,
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
  for (final expected in plan.records) {
    for (final value in expected.values.entries) {
      if (attachmentFields[expected.collectionId]!.contains(value.key)) {
        expectedLinks += (value.value as List).length;
      } else {
        expectedValues++;
      }
    }
    final actual = await SqliteRecordingRepository._loadRecord(db, expected.id);
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
  for (final expected in plan.attachments) {
    final rows = await db.query(
      'attachments',
      where: 'id = ?',
      whereArgs: [expected.id],
    );
    if (rows.length != 1 ||
        rows.single['kind'] != expected.kind.name ||
        rows.single['locator'] != expected.locator ||
        rows.single['name'] != expected.name) {
      throw StateError('A staged attachment differs from the plan.');
    }
  }
}
