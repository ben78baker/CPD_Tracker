part of 'sqlite_recording_repository.dart';

const _collectionLineage = 'recording.collection.origin';
const _evidenceFingerprints = 'recording.evidence.sha256';
const _unavailableEvidence = 'recording.evidence.unavailable';

String _entityOrigin(String entity, String collectionId) =>
    'recording.$entity.origin:$collectionId';

typedef CollectionSetting = ({String namespace, String key, String value});
typedef ProjectCollectionSettings =
    Future<List<CollectionSetting>> Function(
      SqliteRecordingRepository source,
      RecordingCollection collection,
      String destinationId,
      List<TemplateVersion> recipes,
    );
typedef CheckCollectionName =
    Future<bool> Function(SqliteRecordingRepository transaction, String label);

enum UnavailableOriginal { missing, damaged, unresolved }

typedef EvidenceGap = ({String name, UnavailableOriginal reason});

enum CollectionImportStatus { added, existing, recoverable, nameInUse }

typedef CollectionImportResult = ({
  CollectionImportStatus status,
  RecordingCollection? collection,
});

class CollectionBackupSummary {
  const CollectionBackupSummary._(
    this.label,
    this.created,
    this.activeRecords,
    this.deletedRecords,
    this.originals,
    this.links,
    this.unavailable,
  );

  final String label;
  final DateTime created;
  final int activeRecords, deletedRecords, originals, links;
  final List<EvidenceGap> unavailable;
  int get recordCount => activeRecords + deletedRecords;
  int get attachmentCount => originals + links + unavailable.length;
}

/// Owns one temporary archive. The host keeps it only through user handoff.
class CollectionBackupExport {
  const CollectionBackupExport._(
    this._folder,
    this._archive,
    this.summary,
    this._available,
  );

  final Directory _folder;
  final File _archive;
  final AvailableStorage _available;
  final CollectionBackupSummary summary;

  Future<File> fileForSharing({
    String? password,
    bool acceptUnavailable = false,
  }) async {
    if (summary.unavailable.isNotEmpty && !acceptUnavailable) {
      throw const BackupException(
        BackupProblem.integrity,
        'Review unavailable evidence before sharing.',
      );
    }
    if (password == null) return _archive;
    return const BackupEncryption().encrypt(
      _archive,
      File(p.join(_folder.path, 'Protected.recordingbackup')),
      password,
      available: _available,
    );
  }

  Future<void> dispose() => _folder.delete(recursive: true);
}

/// Verified data owned by a restore attempt, including the isolated SQL graph.
/// The original provider file is never modified.
class CollectionBackupReview {
  const CollectionBackupReview._(
    this._folder,
    this._workspace,
    this._sourceId,
    this._lineage,
    this.summary,
  );

  final Directory _folder;
  final RecordingWorkspace _workspace;
  final String _sourceId, _lineage;
  final CollectionBackupSummary summary;

  Future<void> dispose() => _folder.delete(recursive: true);
}

class SqliteCollectionBackup {
  const SqliteCollectionBackup({
    required this.available,
    this.projectSettings,
    this.verifyHost,
    this.factory,
  });

  final AvailableStorage available;
  final ProjectCollectionSettings? projectSettings;
  final VerifyBackupHost? verifyHost;
  final DatabaseFactory? factory;
  static const _archive = PortableArchive();
  static const encryption = BackupEncryption();
  static const _reserve = 4 * 1024 * 1024;
  static final _digest = RegExp(r'^[a-f0-9]{64}$');

  SqliteRecordingBackup get _codec => SqliteRecordingBackup(
    available: available,
    verifyHost: verifyHost,
    factory: factory,
  );

  /// Callers keep managed originals immutable and pin references until capture
  /// completes. The temporary database contains only the selected graph.
  Future<CollectionBackupExport> create({
    required SqliteRecordingRepository repository,
    required String collectionId,
    required Directory originals,
    required Directory temporary,
  }) async {
    await requireBackupCapacity(temporary, _reserve, available);
    final folder = await temporary.createTemp('collection-export-');
    final scope = RecordingWorkspace(folder);
    final archive = File(p.join(folder.path, 'Profession.recordingbackup'));
    final digests = <String, String>{};
    try {
      final target = await SqliteRecordingRepository.open(
        scope.databasePath,
        factory: factory,
      );
      late CollectionBackupSummary summary;
      try {
        final lineage = await repository.transaction((source) async {
          final collection = await source.loadCollection(collectionId);
          if (collection == null) _badRows();
          final graph = await _CollectionGraph.read(source, collection);
          await target.transaction(
            (tx) => _copyGraph(
              graph: graph,
              source: source,
              target: tx,
              id: collectionId,
              label: collection.label,
              originals: originals,
              digests: digests,
            ),
          );
          return (await source.loadHostState(
                _collectionLineage,
              ))[collectionId] ??
              collectionId;
        });
        final inspection = await _codec.create(
          repository: target,
          originals: originals,
          destination: archive,
          collection: {
            'kind': 'recording-collection',
            'id': collectionId,
            'lineage': lineage,
          },
          evidenceDigests: digests,
        );
        summary = await _summary(target, collectionId, inspection.created);
      } finally {
        await target.close();
      }
      await File(scope.databasePath).delete();
      return CollectionBackupExport._(folder, archive, summary, available);
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<CollectionBackupReview> inspect({
    required File source,
    required Directory temporary,
    String? password,
  }) async {
    await requireBackupCapacity(temporary, _reserve, available);
    final folder = await temporary.createTemp('collection-review-');
    File? decrypted;
    try {
      if (await encryption.isEncrypted(source)) {
        if (password == null) {
          throw const BackupException(
            BackupProblem.authentication,
            'A backup password is required.',
          );
        }
        decrypted = await encryption.decrypt(
          source,
          File(p.join(folder.path, 'clear')),
          password,
          available: available,
        );
      }
      final input = decrypted ?? source;
      final inspection = await _archive.inspect(input);
      final metadata = inspection.collection;
      if (metadata == null || metadata['kind'] != 'recording-collection') {
        throw const BackupException(
          BackupProblem.version,
          'Select a single-profession backup.',
        );
      }
      final id = metadata['id'];
      final lineage = metadata['lineage'];
      if (!_validIdentity(id) || !_validIdentity(lineage)) _badRows();
      final workspace = await _codec._restore(
        input,
        inspection,
        Directory(p.join(folder.path, 'candidate')),
        collection: true,
      );
      final db = await SqliteRecordingRepository.open(
        workspace.databasePath,
        factory: factory,
      );
      try {
        final collection = (await db.loadCollections()).single;
        if (collection.id != id) _badRows();
        final graph = await _CollectionGraph.read(db, collection);
        await _verifyScope(
          db,
          graph,
          inspection.originals,
          workspace.originals,
        );
        final summary = await _summary(db, collection.id, inspection.created);
        await decrypted?.delete();
        return CollectionBackupReview._(
          folder,
          workspace,
          collection.id,
          lineage as String,
          summary,
        );
      } finally {
        await db.close();
      }
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  /// Bindings and receipts are committed together. Retrying an acknowledged
  /// lineage finds the existing tile. Removing the tile removes that barrier.
  Future<CollectionImportResult> restore({
    required CollectionBackupReview review,
    required SqliteRecordingRepository repository,
    required ManagedAttachmentFiles originals,
    required String label,
    CheckCollectionName? canUseName,
    Future<void> Function()? beforeCommit,
  }) async {
    if (originals.syncDirectory == null) {
      throw ArgumentError('Restore requires durable original publication.');
    }
    final source = await SqliteRecordingRepository.open(
      review._workspace.databasePath,
      factory: factory,
    );
    var stagedFiles = false;
    final planned = <String, RecordingAttachment>{};
    final id = SqliteRecordingRepository._uuid.v4();
    try {
      final collection = await source.loadCollection(review._sourceId);
      if (collection == null) _badRows();
      final graph = await _CollectionGraph.read(source, collection);
      final preliminary = await repository.transaction(
        (tx) => _conflict(tx, review._lineage, label, canUseName),
      );
      if (preliminary != null) return preliminary;
      var required = _reserve;
      await for (final row in graph.attachments) {
        final attachment = _decodeBackupAttachment(row);
        if (attachment.kind == AttachmentKind.managed) {
          required += await (await _strictOriginal(
            review._workspace.originals,
            attachment.locator,
          )).length();
        }
      }
      await requireBackupCapacity(originals.root, required, available);
      await for (final row in graph.attachments) {
        final attachment = _decodeBackupAttachment(row);
        if (attachment.kind == AttachmentKind.managed) {
          final input = await _strictOriginal(
            review._workspace.originals,
            attachment.locator,
          );
          stagedFiles = true;
          final next = await originals.copyOriginal(
            input,
            displayName: attachment.name,
            importId: id,
          );
          if (next.originalFingerprint !=
              await _fingerprint(source, attachment.id)) {
            _badRows();
          }
          planned[attachment.id] = next;
        } else {
          planned[attachment.id] = RecordingAttachment(
            id: SqliteRecordingRepository._uuid.v4(),
            kind: attachment.kind,
            locator: attachment.locator,
            name: attachment.name,
          );
        }
      }
      // On process termination unlinked originals remain available for
      // conservative orphan reconciliation. They cannot produce a partial tile.
      return await repository.transaction((target) async {
        final conflict = await _conflict(
          target,
          review._lineage,
          label,
          canUseName,
        );
        if (conflict != null) return conflict;
        await _copyGraph(
          graph: graph,
          source: source,
          target: target,
          id: id,
          label: label,
          originals: review._workspace.originals,
          remapped: planned,
        );
        await target.saveHostValue(_collectionLineage, id, review._lineage);
        await beforeCommit?.call();
        return (
          status: CollectionImportStatus.added,
          collection: await target.loadCollection(id),
        );
      });
    } finally {
      await source.close();
      if (stagedFiles) {
        // If COMMIT returned an ambiguous I/O error, preserve files until the
        // database can prove that this attempt did not commit.
        try {
          await _discardUncommitted(repository, originals.root, id);
        } on Object {
          // The exclusive cold-start pass can retry when storage is readable.
        }
      }
    }
  }

  /// Run only at exclusive cold start, before accepting new recording writes.
  /// This namespace holds only files produced by a restore attempt.
  Future<void> reconcileInterruptedRestores(
    SqliteRecordingRepository repository,
    Directory originals,
  ) async {
    final parent = Directory(
      p.join(originals.path, ManagedAttachmentFiles.restoredOriginals),
    );
    if (await FileSystemEntity.type(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await for (final item in parent.list(followLinks: false)) {
      final id = p.basename(item.path);
      if (item is Directory &&
          ManagedAttachmentFiles.importIdPattern.hasMatch(id)) {
        await _discardUncommitted(repository, originals, id);
      }
    }
  }

  Future<void> _discardUncommitted(
    SqliteRecordingRepository repository,
    Directory originals,
    String id,
  ) async {
    if (await repository.loadCollection(id) != null) return;
    final group = ManagedAttachmentFiles.restoredOriginals;
    final referenced = await repository._db.query(
      'attachments',
      columns: ['id'],
      where: 'locator LIKE ?',
      whereArgs: ['$group/$id/%'],
      limit: 1,
    );
    if (referenced.isNotEmpty) return;
    final parent = Directory(p.join(originals.path, group));
    if (await FileSystemEntity.type(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final folder = Directory(p.join(parent.path, id));
    if (await FileSystemEntity.type(folder.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await folder.delete(recursive: true);
    }
  }

  /// Permanently removes an already deleted collection graph. Its lineage is
  /// released in the same transaction. Originals remain for normal reference
  /// reconciliation, which can account for links from other collections.
  Future<void> purgeDeletedCollection(
    SqliteRecordingRepository repository,
    String id,
  ) => repository.transaction((tx) async {
    final collection = await tx.loadCollection(id);
    if (collection == null) return;
    if (!collection.deleted) {
      throw StateError('Delete the collection before purging it.');
    }
    final graph = await _CollectionGraph.read(tx, collection);
    for (final setting in await _settings(tx, graph, id)) {
      // Shared historical rule envelopes remain available to other users of the recipe.
      final shared = (await tx.loadHostState(setting.namespace))[setting.key];
      if (shared == setting.value &&
          (setting.key == id ||
              setting.key.startsWith('$id:') ||
              setting.namespace.endsWith(':$id'))) {
        await tx.removeHostValue(setting.namespace, setting.key);
      }
    }
    final db = tx._db;
    final assets = await graph.attachments
        .map((row) => row['id'] as String)
        .toList();
    for (final table in ['attachment_links', 'record_values']) {
      await db.delete(
        table,
        where: 'record_id IN (SELECT id FROM records WHERE collection_id = ?)',
        whereArgs: [id],
      );
    }
    for (final table in ['records', 'layouts']) {
      await db.delete(table, where: 'collection_id = ?', whereArgs: [id]);
    }
    for (final asset in assets) {
      final removed = await db.delete(
        'attachments',
        where:
            'id = ? AND NOT EXISTS '
            '(SELECT 1 FROM attachment_links WHERE attachment_id = ?)',
        whereArgs: [asset, asset],
      );
      if (removed > 0) {
        await tx.removeHostValue(_evidenceFingerprints, asset);
        await tx.removeHostValue(_unavailableEvidence, asset);
      }
    }
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
    for (final entity in ['record', 'attachment']) {
      await db.delete(
        'host_state',
        where: 'namespace = ?',
        whereArgs: [_entityOrigin(entity, id)],
      );
    }
    await tx.removeHostValue(_collectionLineage, id);
  });

  Future<CollectionImportResult?> _conflict(
    SqliteRecordingRepository tx,
    String lineage,
    String label,
    CheckCollectionName? canUseName,
  ) async {
    final origins = await tx.loadHostState(_collectionLineage);
    final all = await tx.loadCollections();
    for (final collection in all) {
      if (lineage == (origins[collection.id] ?? collection.id)) {
        return (
          status: collection.deleted
              ? CollectionImportStatus.recoverable
              : CollectionImportStatus.existing,
          collection: collection,
        );
      }
    }
    final allowed = canUseName == null
        ? label.trim().isNotEmpty &&
              !all.any(
                (item) => item.label.toLowerCase() == label.toLowerCase(),
              )
        : await canUseName(tx, label);
    return allowed
        ? null
        : (status: CollectionImportStatus.nameInUse, collection: null);
  }

  Future<void> _verifyScope(
    SqliteRecordingRepository source,
    _CollectionGraph graph,
    int originalCount,
    Directory originals,
  ) async {
    final db = source._db;
    for (final (table, count) in [
      ('collections', 1),
      ('templates', graph.recipes.length),
      ('definitions', graph.definitions.length),
      ('import_snapshots', 0),
      ('import_payload_chunks', 0),
    ]) {
      if ((await db.rawQuery(
            'SELECT count(*) FROM $table',
          )).single.values.single !=
          count) {
        _badRows();
      }
    }
    final expected = <(String, String), String>{
      for (final setting in await _settings(source, graph, graph.collection.id))
        (setting.namespace, setting.key): setting.value,
    };
    for (final (entity, rows) in [
      ('record', graph.rows('records')),
      ('attachment', graph.attachments),
    ]) {
      final namespace = _entityOrigin(entity, graph.collection.id);
      final origins = await source.loadHostState(namespace);
      await for (final row in rows) {
        final key = row['id'] as String;
        if (origins[key] case final value?) {
          if (!_validIdentity(value)) _badRows();
          expected[(namespace, key)] = value;
        }
      }
    }
    final fingerprints = await source.loadHostState(_evidenceFingerprints);
    final gaps = await source.loadHostState(_unavailableEvidence);
    final known = <String>{};
    final locators = <String>{};
    await for (final row in graph.attachments) {
      final item = _decodeBackupAttachment(row);
      known.add(item.id);
      if (item.kind == AttachmentKind.managed) {
        final digest = fingerprints[item.id];
        final original = await _strictOriginal(originals, item.locator);
        if (digest == null ||
            !_digest.hasMatch(digest) ||
            await backupDigest(original) != digest ||
            gaps.containsKey(item.id)) {
          _badRows();
        }
        locators.add(item.locator);
        expected[(_evidenceFingerprints, item.id)] = digest;
      } else if (item.kind == AttachmentKind.unresolved) {
        final reason = gaps[item.id];
        if (!UnavailableOriginal.values.any((entry) => entry.name == reason)) {
          _badRows();
        }
        expected[(_unavailableEvidence, item.id)] = reason!;
      }
    }
    if (locators.length != originalCount ||
        (await db.rawQuery(
              'SELECT count(*) FROM attachments',
            )).single.values.single !=
            known.length) {
      _badRows();
    }
    await for (final row in _pages(db, 'host_state')) {
      if (expected.remove((row['namespace'], row['key'])) != row['value']) {
        _badRows();
      }
    }
    if (expected.isNotEmpty) _badRows();
  }

  Future<List<CollectionSetting>> _settings(
    SqliteRecordingRepository source,
    _CollectionGraph graph,
    String id,
  ) async =>
      await projectSettings?.call(
        source,
        graph.collection,
        id,
        graph.recipes,
      ) ??
      const [];

  Future<void> _copyGraph({
    required _CollectionGraph graph,
    required SqliteRecordingRepository source,
    required SqliteRecordingRepository target,
    required String id,
    required String label,
    required Directory originals,
    Map<String, String>? digests,
    Map<String, RecordingAttachment>? remapped,
  }) async {
    final db = target._db;
    for (final definition in graph.definitions.values) {
      final rows = await db.query(
        'definitions',
        where: 'id = ? AND version = ?',
        whereArgs: [definition.id, definition.version],
      );
      if (rows.isEmpty) {
        await db.insert('definitions', {
          'id': definition.id,
          'version': definition.version,
          'payload': jsonEncode(definition.toJson()),
        });
      } else if (jsonEncode(
            FieldDefinition.fromJson(
              jsonDecode(rows.single['payload'] as String)
                  as Map<String, dynamic>,
            ).toJson(),
          ) !=
          jsonEncode(definition.toJson())) {
        _badRows();
      }
    }
    for (final recipe in graph.recipes) {
      final existing = await target.loadTemplate(recipe.id, recipe.version);
      if (existing == null) {
        await db.insert('templates', {
          'id': recipe.id,
          'version': recipe.version,
          'label': recipe.label,
          'fields': _encodeFields(recipe.fields),
          'settings': jsonEncode(recipe.settingsToJson()),
        });
      } else if (existing.label != recipe.label ||
          _encodeFields(existing.fields) != _encodeFields(recipe.fields) ||
          jsonEncode(existing.settingsToJson()) !=
              jsonEncode(recipe.settingsToJson())) {
        _badRows();
      }
    }
    await SqliteRecordingRepository._insertCollection(
      db,
      RecordingCollection(id, label, graph.collection.layoutVersion),
    );
    await for (final row in graph.rows('layouts')) {
      await db.insert('layouts', {...row, 'collection_id': id});
    }
    final recordIds = <String, String>{};
    final recordOrigins = await source.loadHostState(
      _entityOrigin('record', graph.collection.id),
    );
    final attachmentOrigins = await source.loadHostState(
      _entityOrigin('attachment', graph.collection.id),
    );
    await for (final row in graph.rows('records')) {
      final old = row['id'] as String;
      final recordId = remapped == null
          ? old
          : SqliteRecordingRepository._uuid.v4();
      recordIds[old] = recordId;
      final origin = recordOrigins[old] ?? (remapped == null ? null : old);
      if (origin != null) {
        await target.saveHostValue(
          _entityOrigin('record', id),
          recordId,
          origin,
        );
      }
      await db.insert('records', {...row, 'id': recordId, 'collection_id': id});
    }
    final attachmentIds = <String, String>{};
    final preserved = await source.loadHostState(_unavailableEvidence);
    final previousDigests = await source.loadHostState(_evidenceFingerprints);
    await for (final row in graph.attachments) {
      var item = _decodeBackupAttachment(row);
      final oldId = item.id;
      var gap = preserved[oldId];
      if (remapped != null) {
        item = remapped[oldId]!;
      } else if (item.kind == AttachmentKind.managed) {
        String? observed;
        try {
          observed = await backupDigest(
            await _strictOriginal(originals, item.locator),
          );
        } on BackupException {
          gap = UnavailableOriginal.missing.name;
        } on FileSystemException {
          gap = UnavailableOriginal.damaged.name;
        }
        if (previousDigests[oldId] case final known?
            when observed != null && observed != known) {
          gap = UnavailableOriginal.damaged.name;
        }
        if (gap == null && observed != null) {
          digests![item.locator] = observed;
          item = RecordingAttachment(
            id: oldId,
            kind: item.kind,
            locator: item.locator,
            name: item.name,
            originalFingerprint: observed,
          );
        } else {
          item = RecordingAttachment(
            id: oldId,
            kind: AttachmentKind.unresolved,
            locator: item.locator,
            name: item.name,
          );
        }
      }
      attachmentIds[oldId] = item.id;
      final origin =
          attachmentOrigins[oldId] ?? (remapped == null ? null : oldId);
      if (origin != null) {
        await target.saveHostValue(
          _entityOrigin('attachment', id),
          item.id,
          origin,
        );
      }
      await SqliteRecordingRepository._insertAttachment(db, item);
      if (item.kind == AttachmentKind.unresolved) {
        await target.saveHostValue(
          _unavailableEvidence,
          item.id,
          gap ?? UnavailableOriginal.unresolved.name,
        );
      }
    }
    for (final table in ['record_values', 'attachment_links']) {
      await for (final row in graph.rows(table)) {
        await db.insert(table, {
          ...row,
          'record_id': recordIds[row['record_id']]!,
          if (table == 'attachment_links')
            'attachment_id': attachmentIds[row['attachment_id']]!,
        });
      }
    }
    for (final setting in await _settings(source, graph, id)) {
      final current = (await target.loadHostState(
        setting.namespace,
      ))[setting.key];
      if (current != null && current != setting.value) _badRows();
      await target.saveHostValue(setting.namespace, setting.key, setting.value);
    }
  }

  Future<String?> _fingerprint(SqliteRecordingRepository db, String id) async {
    final rows = await db._db.query(
      'host_state',
      columns: ['value'],
      where: 'namespace = ? AND key = ?',
      whereArgs: [_evidenceFingerprints, id],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<CollectionBackupSummary> _summary(
    SqliteRecordingRepository db,
    String id,
    DateTime created,
  ) async {
    final collection = await db.loadCollection(id);
    if (collection == null) _badRows();
    final counts = await db._db.rawQuery(
      'SELECT deleted, count(*) AS total FROM records WHERE collection_id = ? GROUP BY deleted',
      [id],
    );
    final byStatus = {
      for (final row in counts) row['deleted']: row['total'] as int,
    };
    final gaps = await db.loadHostState(_unavailableEvidence);
    final issues = <EvidenceGap>[];
    var originals = 0;
    var links = 0;
    await for (final row in _pages(db._db, 'attachments')) {
      final item = _decodeBackupAttachment(row);
      switch (item.kind) {
        case AttachmentKind.managed:
          originals++;
        case AttachmentKind.link:
          links++;
        case AttachmentKind.unresolved:
          issues.add((
            name: item.name,
            reason: UnavailableOriginal.values.byName(gaps[item.id]!),
          ));
      }
    }
    return CollectionBackupSummary._(
      collection.label,
      created,
      byStatus[0] ?? 0,
      byStatus[1] ?? 0,
      originals,
      links,
      List.unmodifiable(issues),
    );
  }

  static bool _validIdentity(Object? value) =>
      value is String && value.trim().isNotEmpty && value.length <= 160;
}

class _CollectionGraph {
  const _CollectionGraph(
    this.db,
    this.collection,
    this.recipes,
    this.definitions,
  );

  final DatabaseExecutor db;
  final RecordingCollection collection;
  final List<TemplateVersion> recipes;
  final Map<(String, int), FieldDefinition> definitions;

  static Future<_CollectionGraph> read(
    SqliteRecordingRepository source,
    RecordingCollection collection,
  ) async {
    final layouts = await source.loadLayouts(collection.id);
    final recipes = <(String, int), TemplateVersion>{};
    final definitions = <(String, int), FieldDefinition>{};
    void retain(LayoutField field) {
      final definition = field.definition;
      final pin = (definition.id, definition.version);
      if (definitions[pin] case final previous?
          when jsonEncode(previous.toJson()) !=
              jsonEncode(definition.toJson())) {
        _badRows();
      }
      definitions[pin] = definition;
    }

    for (final layout in layouts) {
      for (final field in layout.fields) {
        retain(field);
      }
      if (layout.templateId case final id?) {
        final version = layout.templateVersion!;
        if (!recipes.containsKey((id, version))) {
          final recipe = await source.loadTemplate(id, version);
          if (recipe == null) _badRows();
          recipes[(id, version)] = recipe;
          for (final field in recipe.fields) {
            retain(field);
          }
        }
      }
    }
    return _CollectionGraph(
      source._db,
      collection,
      recipes.values.toList(),
      definitions,
    );
  }

  Stream<Map<String, Object?>> get attachments => _scopedRows(
    'attachments',
    'EXISTS (SELECT 1 FROM attachment_links l JOIN records r '
        'ON r.id = l.record_id WHERE l.attachment_id = t.id AND r.collection_id = ?)',
  );

  Stream<Map<String, Object?>> rows(
    String table,
  ) => _scopedRows(table, switch (table) {
    'layouts' || 'records' => 't.collection_id = ?',
    'record_values' || 'attachment_links' =>
      'EXISTS (SELECT 1 FROM records r WHERE r.id = t.record_id AND r.collection_id = ?)',
    _ => throw ArgumentError.value(table),
  });

  Stream<Map<String, Object?>> _scopedRows(
    String table,
    String predicate,
  ) async* {
    var cursor = 0;
    while (true) {
      final page = await db.rawQuery(
        'SELECT t.rowid AS backup_rowid, t.* FROM $table t '
        'WHERE t.rowid > ? AND $predicate ORDER BY t.rowid LIMIT 64',
        [cursor, collection.id],
      );
      if (page.isEmpty) return;
      for (final row in page) {
        cursor = row['backup_rowid'] as int;
        yield Map.of(row)..remove('backup_rowid');
      }
    }
  }
}
