import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../cpd_migration/legacy_migration.dart';
import '../models.dart';
import '../recording_engine/import_plan.dart';
import '../recording_engine/models.dart';
import '../recording_engine_storage/managed_attachment_files.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'cpd_data_store.dart';

/// Compatibility writer for an explicitly supplied, verified staging database.
/// The shipping app continues to construct its SharedPreferences stores.
class SqliteCpdStore extends CpdDataStore {
  SqliteCpdStore._(this._db, this._files);

  final SqliteRecordingRepository _db;
  final ManagedAttachmentFiles _files;
  static const _prefs = 'cpd.preferences';
  static const _rows = 'cpd.records';
  static const _uuid = Uuid();

  static Future<SqliteCpdStore> openVerified(
    SqliteRecordingRepository db, {
    required String sourceId,
    required Directory documents,
  }) async {
    await db.transaction((tx) async {
      final snapshot = await tx.loadImportSnapshot(sourceId);
      if (snapshot?.status != ImportStatus.verified) {
        throw StateError('A verified legacy snapshot is required.');
      }
      final settings = await tx.loadHostState(_prefs);
      if (settings.isNotEmpty) {
        if (settings['source'] != sourceId) {
          throw StateError(
            'This CPD projection belongs to a different source.',
          );
        }
        return;
      }
      final metadata = _object(jsonDecode(snapshot!.metadata!));
      final raw = _object(jsonDecode(snapshot.raw));
      final sourceRows = (raw['entries_json_list'] as List?) ?? const [];
      final mapping = metadata['records'] as List;
      if (mapping.length != sourceRows.length) {
        throw StateError('The verified source row mapping is incomplete.');
      }
      final records = {
        for (final record in await tx.loadAllRecords()) record.id: record,
      };
      final revisions = <String, List<LayoutRevision>>{};
      var nextId = (raw['next_entry_id'] as int?) ?? 1;
      for (final (index, row) in mapping.indexed) {
        final link = _object(row);
        if (link['row'] != index) throw StateError('Invalid source row order.');
        final entry = CpdEntry.fromJson(sourceRows[index] as String);
        final id = link['id'] as String;
        final record = records[id]!;
        final fields = await _fieldsFor(tx, record, revisions: revisions);
        final assets = _assetIds(record, fields);
        if (entry.id != link['legacyId'] ||
            assets.length != entry.attachments.length) {
          throw StateError(
            'Source row provenance does not match its projection.',
          );
        }
        await _saveRow(
          tx,
          id,
          _LegacyRow(
            id: entry.id,
            ordinal: index,
            profession: entry.profession,
            references: {
              for (final (order, asset) in assets.indexed)
                asset: entry.attachments[order],
            },
          ),
        );
        if (entry.id >= nextId) nextId = _advance(entry.id);
      }
      for (final setting in {
        'source': sourceId,
        'professions': jsonEncode(raw['professions'] ?? []),
        'deleted': jsonEncode(raw['deleted_professions'] ?? []),
        'targets': (raw['targets_v1'] as String?)?.isNotEmpty == true
            ? raw['targets_v1'] as String
            : '{}',
        'nextId': '$nextId',
        'nextOrdinal': '${mapping.length}',
      }.entries) {
        await tx.saveHostValue(_prefs, setting.key, setting.value);
      }
    });
    return SqliteCpdStore._(db, ManagedAttachmentFiles(documents));
  }

  /// Check the actual compatibility surface before any authority switch.
  Future<void> verifyLegacyProjection(Map<String, Object?> raw) async {
    final expected = ((raw['entries_json_list'] as List?) ?? const [])
        .cast<String>();
    final projected = await loadAll();
    if (projected.length != expected.length) {
      throw StateError('The CPD projection has a different record count.');
    }
    for (final (index, entry) in projected.indexed) {
      if (entry.toJson() != CpdEntry.fromJson(expected[index]).toJson()) {
        throw StateError('The CPD projection differs from a source record.');
      }
    }
    final settings = await _db.loadHostState(_prefs);
    final rawTargets = raw['targets_v1'] as String?;
    if (settings['targets'] !=
            (rawTargets?.isNotEmpty == true ? rawTargets : '{}') ||
        settings['professions'] != jsonEncode(raw['professions'] ?? []) ||
        settings['deleted'] != jsonEncode(raw['deleted_professions'] ?? [])) {
      throw StateError(
        'The CPD profession settings or targets differ from the source.',
      );
    }
  }

  @override
  Future<List<CpdEntry>> loadAll() => _db.transaction((tx) async {
    final mappings = await _loadRows(tx);
    final ordered = mappings.entries.toList()
      ..sort((a, b) => a.value.ordinal.compareTo(b.value.ordinal));
    final records = {
      for (final record in await tx.loadAllRecords()) record.id: record,
    };
    if (records.length != mappings.length) {
      throw StateError('The recording graph has unmapped records.');
    }
    final revisions = <String, List<LayoutRevision>>{};
    return [
      for (final row in ordered)
        await _project(
          tx,
          row.key,
          row.value,
          record: records[row.key],
          revisions: revisions,
        ),
    ];
  });

  static Future<CpdEntry> _project(
    SqliteRecordingRepository tx,
    String id,
    _LegacyRow row, {
    RecordingRecord? record,
    Map<String, List<LayoutRevision>>? revisions,
  }) async {
    record ??= await tx.loadRecord(id);
    if (record == null) throw StateError('A mapped record is missing.');
    final fields = await _fieldsFor(tx, record, revisions: revisions);
    final total = record.values[fields['cpd.creditedDuration']] as int;
    return CpdEntry(
      id: row.id,
      profession: row.profession,
      date: DateTime.parse(record.values[fields['cpd.activityDate']] as String),
      title: record.values[fields['cpd.title']] as String? ?? '',
      details: record.values[fields['cpd.details']] as String? ?? '',
      hours: total ~/ 60,
      minutes: total % 60,
      attachments: [
        for (final asset in _assetIds(record, fields))
          row.references[asset] ?? (await tx.loadAttachment(asset))!.locator,
      ],
      deleted: record.deleted,
    );
  }

  @override
  Future<CpdEntry> createAndSave({
    required String profession,
    required DateTime date,
    required String title,
    required String details,
    required int hours,
    required int minutes,
    required List<String> attachments,
  }) => _db.transaction((tx) async {
    final settings = await tx.loadHostState(_prefs);
    final entry = CpdEntry(
      id: int.parse(settings['nextId']!),
      profession: profession,
      date: date,
      title: title,
      details: details,
      hours: hours,
      minutes: minutes,
      attachments: attachments,
    );
    await _insert(tx, entry, settings);
    return entry;
  });

  @override
  Future<void> saveEntry(CpdEntry entry) => _db.transaction((tx) async {
    if (_findRow(await _loadRows(tx), entry.id) != null) {
      throw StateError('This CPD entry ID is already in use.');
    }
    await _insert(tx, entry, await tx.loadHostState(_prefs));
  });

  Future<void> _insert(
    SqliteRecordingRepository tx,
    CpdEntry entry,
    Map<String, String> settings,
  ) async {
    final group = await _findProfession(tx, entry.profession);
    if (group == null || group.deleted) {
      throw StateError('An active profession is required.');
    }
    final layout = (await tx.loadLayouts(group.id)).last;
    final fields = _bindings(layout.fields);
    final assets = await _describeAttachments(entry.attachments);
    final values = _values(entry, fields);
    if (assets.isNotEmpty) {
      values[fields['cpd.evidence']!] = assets
          .map((asset) => asset.id)
          .toList();
    }
    final record = await tx.createRecord(
      group.id,
      values,
      expectedLayoutVersion: group.layoutVersion,
      newAttachments: assets,
    );
    if (entry.deleted) {
      await tx.setRecordDeleted(
        record.id,
        true,
        expectedVersion: record.version,
      );
    }
    final ordinal = int.parse(settings['nextOrdinal']!);
    await _saveRow(
      tx,
      record.id,
      _LegacyRow(
        id: entry.id,
        ordinal: ordinal,
        profession: entry.profession,
        references: _references(assets, entry.attachments),
      ),
    );
    await tx.saveHostValue(_prefs, 'nextOrdinal', '${_advance(ordinal)}');
    if (entry.id >= int.parse(settings['nextId']!)) {
      await tx.saveHostValue(_prefs, 'nextId', '${_advance(entry.id)}');
    }
  }

  @override
  Future<void> updateEntry(CpdEntry updated) => _db.transaction((tx) async {
    final mapping = _findRow(await _loadRows(tx), updated.id);
    if (mapping == null) {
      return _insert(tx, updated, await tx.loadHostState(_prefs));
    }
    var record = (await tx.loadRecord(mapping.key))!;
    final previous = await _project(tx, mapping.key, mapping.value);
    if (cpdProfessionKey(previous.profession) !=
        cpdProfessionKey(updated.profession)) {
      throw StateError(
        'The editor cannot move a record to another profession.',
      );
    }
    final fields = await _fieldsFor(tx, record);
    final changes = <String, Object?>{..._values(updated, fields)};
    var references = mapping.value.references;
    final newAssets = <RecordingAttachment>[];
    if (!_sameStrings(previous.attachments, updated.attachments)) {
      final available = <String, List<String>>{};
      for (final (index, asset) in _assetIds(record, fields).indexed) {
        (available[previous.attachments[index]] ??= []).add(asset);
      }
      references = {};
      final ordered = <String>[];
      for (final ref in updated.attachments) {
        final candidates = available[ref];
        final String id;
        if (candidates != null && candidates.isNotEmpty) {
          id = candidates.removeAt(0);
        } else {
          final asset = await classifyLegacyAttachment(_files, _uuid.v4(), ref);
          newAssets.add(asset);
          id = asset.id;
        }
        ordered.add(id);
        references[id] = ref;
      }
      changes[fields['cpd.evidence']!] = ordered.isEmpty ? null : ordered;
    }
    if (record.deleted) {
      await tx.setRecordDeleted(
        record.id,
        false,
        expectedVersion: record.version,
      );
      record = (await tx.loadRecord(record.id))!;
    }
    final saved = await tx.updateValues(
      record.id,
      changes,
      expectedVersion: record.version,
      newAttachments: newAssets,
    );
    if (updated.deleted) {
      await tx.setRecordDeleted(saved.id, true, expectedVersion: saved.version);
    }
    await _saveRow(
      tx,
      record.id,
      _LegacyRow(
        id: updated.id,
        ordinal: mapping.value.ordinal,
        profession: updated.profession,
        references: references,
      ),
    );
  });

  @override
  Future<void> setDeleted(int id, bool deleted) => _db.transaction((tx) async {
    final mapping = _findRow(await _loadRows(tx), id);
    if (mapping == null) return;
    final record = (await tx.loadRecord(mapping.key))!;
    await tx.setRecordDeleted(
      record.id,
      deleted,
      expectedVersion: record.version,
    );
  });

  @override
  Future<void> restoreRecord(int id, {bool recoverProfession = false}) =>
      _db.transaction((tx) async {
        final mapping = _findRow(await _loadRows(tx), id);
        if (mapping == null) {
          throw StateError('The saved record could not be identified safely.');
        }
        final record = (await tx.loadRecord(mapping.key))!;
        final label = mapping.value.profession;
        final settings = await tx.loadHostState(_prefs);
        if (!_active(
          settings,
        ).any((name) => cpdProfessionKey(name) == cpdProfessionKey(label))) {
          if (!recoverProfession) {
            throw StateError('Restore this profession first.');
          }
          await _changeProfession(tx, settings, label, deleted: false);
        }
        await tx.setRecordDeleted(
          record.id,
          false,
          expectedVersion: record.version,
        );
      });

  @override
  Future<List<String>> loadProfessions() async =>
      _labels(await _db.loadHostState(_prefs), 'professions');

  @override
  Future<List<String>> loadDeletedProfessions() async =>
      _canonical(_labels(await _db.loadHostState(_prefs), 'deleted'));

  @override
  Future<List<String>> loadActiveProfessions() async =>
      _active(await _db.loadHostState(_prefs));

  @override
  Future<void> addProfession(String value) => _db.transaction((tx) async {
    final label = cpdProfessionLabel(value);
    final settings = await tx.loadHostState(_prefs);
    final names = _labels(settings, 'professions');
    if (label.isEmpty ||
        names.any((name) => name.toLowerCase() == label.toLowerCase())) {
      return;
    }
    final group = await _findProfession(tx, label);
    final deleted = _canonical(
      _labels(settings, 'deleted'),
    ).any((name) => name.toLowerCase() == label.toLowerCase());
    await _ensureProfession(tx, group, label, deleted: deleted);
    await _saveLabels(tx, 'professions', [...names, label]);
  });

  @override
  Future<void> softDeleteProfession(String value) =>
      _db.transaction((tx) async {
        await _changeProfession(
          tx,
          await tx.loadHostState(_prefs),
          value,
          deleted: true,
        );
      });

  @override
  Future<void> restoreProfession(String value) => _db.transaction((tx) async {
    await _changeProfession(
      tx,
      await tx.loadHostState(_prefs),
      value,
      deleted: false,
    );
  });

  static Future<void> _changeProfession(
    SqliteRecordingRepository tx,
    Map<String, String> settings,
    String value, {
    required bool deleted,
  }) async {
    final label = cpdProfessionLabel(value);
    if (label.isEmpty) return;
    final key = cpdProfessionKey(label);
    final group = await _findProfession(tx, label);
    await _ensureProfession(tx, group, label, deleted: deleted);
    final names = _labels(settings, 'professions');
    if (!names.any((name) => name.toLowerCase() == key)) {
      await _saveLabels(tx, 'professions', [...names, label]);
    }
    final archived = _labels(
      settings,
      'deleted',
    ).where((name) => cpdProfessionKey(name) != key);
    await _saveLabels(tx, 'deleted', [...archived, if (deleted) label]);
  }

  static Future<void> _ensureProfession(
    SqliteRecordingRepository tx,
    RecordingCollection? group,
    String label, {
    required bool deleted,
  }) async {
    final collection =
        group ??
        await tx.createCollection(label, fields: cpdStandardFields(_uuid.v4()));
    await tx.updateCollection(collection.id, deleted: deleted);
  }

  @override
  Future<void> renameProfession(
    String oldValue,
    String newValue,
  ) => _db.transaction((tx) async {
    final oldKey = cpdProfessionKey(oldValue);
    final name = cpdProfessionLabel(newValue);
    final key = cpdProfessionKey(name);
    if (key.isEmpty) throw StateError('Please enter a profession name.');
    final settings = await tx.loadHostState(_prefs);
    final names = _labels(settings, 'professions');
    if (!names.any((label) => cpdProfessionKey(label) == oldKey)) {
      throw StateError('This profession no longer exists.');
    }
    final all = await tx.loadCollections();
    final existing = all
        .where((group) => cpdProfessionKey(group.label) == oldKey)
        .single;
    final targets = _targets(settings);
    if (key != oldKey &&
        (all.any((group) => cpdProfessionKey(group.label) == key) ||
            targets.keys.any((target) => cpdProfessionKey(target) == key))) {
      throw StateError('That profession name already has saved data.');
    }
    final source = targets.keys
        .where((target) => cpdProfessionKey(target) == oldKey)
        .toList();
    if (source.length > 1) {
      throw StateError('This profession has conflicting saved targets.');
    }
    if (source.isNotEmpty) targets[name] = targets.remove(source.single);
    await tx.updateCollection(existing.id, label: name);
    for (final row in (await _loadRows(tx)).entries) {
      if (cpdProfessionKey(row.value.profession) == oldKey) {
        await _saveRow(tx, row.key, row.value.renamed(name));
      }
    }
    await _saveLabels(
      tx,
      'professions',
      names.map((label) => cpdProfessionKey(label) == oldKey ? name : label),
    );
    await _saveLabels(
      tx,
      'deleted',
      _labels(
        settings,
        'deleted',
      ).map((label) => cpdProfessionKey(label) == oldKey ? name : label),
    );
    await tx.saveHostValue(_prefs, 'targets', jsonEncode(targets));
  });

  @override
  Future<(int, String)?> getTarget(String profession) async {
    final item = _targets(await _db.loadHostState(_prefs))[profession];
    if (item == null) return null;
    final target = _object(item);
    return (
      (target['minutes'] ?? 0) as int,
      (target['cycle'] ?? 'week') as String,
    );
  }

  @override
  Future<void> setTarget(
    String profession, {
    required int minutes,
    required String cycle,
  }) => _db.transaction((tx) async {
    if (minutes < 0 || !cpdTargetCycles.contains(cycle)) {
      throw ArgumentError('Invalid CPD target.');
    }
    final targets = _targets(await tx.loadHostState(_prefs));
    targets[profession] = {'minutes': minutes, 'cycle': cycle};
    await tx.saveHostValue(_prefs, 'targets', jsonEncode(targets));
  });

  @override
  Future<void> clearTarget(String profession) => _db.transaction((tx) async {
    final targets = _targets(await tx.loadHostState(_prefs));
    targets.remove(profession);
    await tx.saveHostValue(_prefs, 'targets', jsonEncode(targets));
  });

  Future<List<RecordingAttachment>> _describeAttachments(
    List<String> references,
  ) async => [
    for (final ref in references)
      await classifyLegacyAttachment(_files, _uuid.v4(), ref),
  ];

  static Map<String, String> _references(
    List<RecordingAttachment> assets,
    List<String> raw,
  ) => {for (final (index, asset) in assets.indexed) asset.id: raw[index]};

  static Future<Map<String, String>> _fieldsFor(
    SqliteRecordingRepository tx,
    RecordingRecord record, {
    Map<String, List<LayoutRevision>>? revisions,
  }) async {
    var layouts = revisions?[record.collectionId];
    if (layouts == null) {
      layouts = await tx.loadLayouts(record.collectionId);
      revisions?[record.collectionId] = layouts;
    }
    return _bindings(resolveFields(record.layoutVersion, layouts));
  }

  static Map<String, String> _bindings(Iterable<LayoutField> fields) {
    const canonical = {
      'cpd.activityDate': FieldKind.date,
      'cpd.title': FieldKind.text,
      'cpd.details': FieldKind.text,
      'cpd.creditedDuration': FieldKind.duration,
      'cpd.evidence': FieldKind.attachments,
    };
    final bindings = <String, String>{};
    for (final field in fields) {
      final id = field.definition.id;
      if (!canonical.containsKey(id)) continue;
      if (canonical[id] != field.definition.kind || bindings.containsKey(id)) {
        throw StateError('A CPD field binding is ambiguous.');
      }
      bindings[id] = field.id;
    }
    if (bindings.length != canonical.length) {
      throw StateError('The layout is missing a protected CPD field.');
    }
    return bindings;
  }

  static List<String> _assetIds(
    RecordingRecord record,
    Map<String, String> fields,
  ) =>
      (record.values[fields['cpd.evidence']] as List?)?.cast<String>() ??
      const [];

  static Map<String, Object> _values(
    CpdEntry entry,
    Map<String, String> fields,
  ) {
    final date = entry.date;
    if (date.isUtc ||
        date != DateTime(date.year, date.month, date.day) ||
        entry.hours < 0 ||
        entry.hours > (0x7fffffffffffffff - 59) ~/ 60 ||
        entry.minutes < 0 ||
        entry.minutes >= 60) {
      throw ArgumentError(
        'CPD dates and durations must have unambiguous legacy values.',
      );
    }
    return {
      fields['cpd.activityDate']!: date.toIso8601String().split('T').first,
      fields['cpd.title']!: entry.title,
      fields['cpd.details']!: entry.details,
      fields['cpd.creditedDuration']!: entry.hours * 60 + entry.minutes,
    };
  }

  static Future<RecordingCollection?> _findProfession(
    SqliteRecordingRepository tx,
    String label,
  ) async {
    final key = cpdProfessionKey(label);
    return (await tx.loadCollections())
        .where((group) => cpdProfessionKey(group.label) == key)
        .singleOrNull;
  }

  static Future<Map<String, _LegacyRow>> _loadRows(
    SqliteRecordingRepository tx,
  ) async => {
    for (final entry in (await tx.loadHostState(_rows)).entries)
      entry.key: _LegacyRow.decode(entry.value),
  };

  static MapEntry<String, _LegacyRow>? _findRow(
    Map<String, _LegacyRow> rows,
    int id,
  ) {
    final matches = rows.entries.where((row) => row.value.id == id).toList();
    if (matches.length > 1) {
      throw StateError('The saved record could not be identified safely.');
    }
    return matches.singleOrNull;
  }

  static Future<void> _saveRow(
    SqliteRecordingRepository tx,
    String id,
    _LegacyRow row,
  ) => tx.saveHostValue(_rows, id, row.encode());

  static Future<void> _saveLabels(
    SqliteRecordingRepository tx,
    String key,
    Iterable<String> names,
  ) => tx.saveHostValue(_prefs, key, jsonEncode(_canonical(names)));

  static List<String> _labels(Map<String, String> state, String key) =>
      (jsonDecode(state[key]!) as List).cast<String>();

  static Map<String, Object?> _targets(Map<String, String> state) =>
      _object(jsonDecode(state['targets']!));

  static List<String> _active(Map<String, String> state) {
    final deleted = _canonical(
      _labels(state, 'deleted'),
    ).map((name) => name.toLowerCase()).toSet();
    return _labels(
        state,
        'professions',
      ).where((name) => !deleted.contains(name.toLowerCase())).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

class _LegacyRow {
  _LegacyRow({
    required this.id,
    required this.ordinal,
    required this.profession,
    required this.references,
  });

  final int id;
  final int ordinal;
  final String profession;
  final Map<String, String> references;

  _LegacyRow renamed(String name) => _LegacyRow(
    id: id,
    ordinal: ordinal,
    profession: name,
    references: references,
  );

  factory _LegacyRow.decode(String raw) {
    final row = _object(jsonDecode(raw));
    return _LegacyRow(
      id: row['id'] as int,
      ordinal: row['ordinal'] as int,
      profession: row['profession'] as String,
      references: (row['references'] as Map).cast<String, String>(),
    );
  }

  String encode() => jsonEncode({
    'id': id,
    'ordinal': ordinal,
    'profession': profession,
    'references': references,
  });
}

Map<String, Object?> _object(Object? value) =>
    (value as Map).cast<String, Object?>();
List<String> _canonical(Iterable<String> names) =>
    names
        .map(cpdProfessionLabel)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

int _advance(int value) {
  if (value == 0x7fffffffffffffff) {
    throw StateError('The legacy sequence is exhausted.');
  }
  return value + 1;
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.indexed.every((value) => value.$2 == right[value.$1]);
