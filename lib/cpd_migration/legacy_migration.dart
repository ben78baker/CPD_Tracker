import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../recording_engine/import_plan.dart';
import '../recording_engine/models.dart';
import '../recording_engine_storage/managed_attachment_files.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';

const _uuid = Uuid();
const _parserVersion = 1;

String _stableId(Object? identity) =>
    _uuid.v5(Namespace.url.value, jsonEncode(['cpd-legacy', identity]));

/// Recovery rehearsal for a supplied synthetic snapshot. There is no live
/// SharedPreferences reader, database path picker, or activation entry point.
class SyntheticCpdMigration {
  SyntheticCpdMigration(this.destination, Directory documents)
    : originals = ManagedAttachmentFiles(documents);

  final SqliteRecordingRepository destination;
  final ManagedAttachmentFiles originals;

  Future<ImportStatus> stage(Map<String, Object?> legacyValues) async {
    final raw = _encodeSnapshot(legacyValues);
    final sourceId = _stableId(raw);
    await destination.captureImport(sourceId, raw);
    final plan = await _plan(sourceId, raw, originals);
    return destination.stageImport(plan);
  }

  Future<ImportSnapshot?> inspect(Map<String, Object?> legacyValues) =>
      destination.loadImportSnapshot(_stableId(_encodeSnapshot(legacyValues)));

  Future<void> verify(Map<String, Object?> legacyValues) async {
    final raw = _encodeSnapshot(legacyValues);
    final plan = await _plan(_stableId(raw), raw, originals);
    final fingerprints = (jsonDecode(plan.metadata) as Map)['originals'] as Map;
    await destination.verifyImport(
      plan,
      verifyManagedOriginal: (attachment) async {
        final file = await originals.resolveOriginal(attachment);
        return file != null &&
            await _fileFingerprint(file) == fingerprints[attachment.id];
      },
    );
  }
}

String _encodeSnapshot(Map<String, Object?> values) => jsonEncode({
  for (final key in values.keys.toList()..sort()) key: values[key],
});

String _normalise(String text) => text.trim().toLowerCase();

const _knownRecordKeys = {
  'id',
  'profession',
  'date',
  'title',
  'details',
  'hours',
  'minutes',
  'attachments',
  'deleted',
};

final _standardFields = [
  FieldDefinition(
    id: 'cpd.activityDate',
    version: 1,
    label: 'Activity date',
    kind: FieldKind.date,
  ),
  FieldDefinition(
    id: 'cpd.title',
    version: 1,
    label: 'Title',
    kind: FieldKind.text,
  ),
  FieldDefinition(
    id: 'cpd.details',
    version: 1,
    label: 'Details',
    kind: FieldKind.text,
    multiline: true,
  ),
  FieldDefinition(
    id: 'cpd.creditedDuration',
    version: 1,
    label: 'CPD duration',
    kind: FieldKind.duration,
  ),
  FieldDefinition(
    id: 'cpd.evidence',
    version: 1,
    label: 'Evidence',
    kind: FieldKind.attachments,
  ),
];

Future<RecordingImportPlan> _plan(
  String sourceId,
  String raw,
  ManagedAttachmentFiles originals,
) async {
  final source = (jsonDecode(raw) as Map).cast<String, Object?>();
  final planner = _LegacyPlanner(sourceId, originals);
  await planner.read(source);
  return RecordingImportPlan(
    sourceId: sourceId,
    rawSnapshot: raw,
    metadata: jsonEncode({
      'parserVersion': _parserVersion,
      'sourceRecordCount': planner.sourceRecordCount,
      'records': planner.recordMapping,
      'collections': {
        for (final entry in planner.groups.entries) entry.key: entry.value.id,
      },
      'targets': planner.targets,
      'originals': planner.fingerprints,
      'issues': planner.issues,
    }),
    blocked: planner.issues.any((issue) => issue['blocks'] == true),
    collections: planner.groups.values.map((group) => group.collection),
    layouts: planner.groups.values.map((group) => group.layout),
    records: planner.records,
    attachments: planner.attachments,
  );
}

class _Group {
  _Group(this.id, this.label, {required this.deleted});

  final String id;
  final String label;
  final bool deleted;
  late final fields = [
    for (final definition in _standardFields)
      LayoutField(
        id: _stableId([id, definition.id]),
        definition: definition,
        required: definition.kind == FieldKind.date,
      ),
  ];

  String field(String definitionId) =>
      fields.singleWhere((field) => field.definition.id == definitionId).id;

  RecordingCollection get collection =>
      RecordingCollection(id, label, 1, deleted: deleted);

  LayoutRevision get layout =>
      LayoutRevision(collectionId: id, version: 1, fields: fields);
}

class _LegacyPlanner {
  _LegacyPlanner(this.sourceId, this.originals);

  final String sourceId;
  final ManagedAttachmentFiles originals;
  final groups = <String, _Group>{};
  final records = <RecordingRecord>[];
  final attachments = <RecordingAttachment>[];
  final fingerprints = <String, String>{};
  final targets = <String, Map<String, Object>>{};
  final recordMapping = <Map<String, Object>>[];
  final issues = <Map<String, Object>>[];
  final seenIds = <int>{};
  var sourceRecordCount = 0;

  void issue(String code, {bool blocks = false, int? row, int? attachment}) {
    issues.add({
      'code': code,
      'blocks': blocks,
      'row': ?row,
      'attachment': ?attachment,
    });
  }

  Future<void> read(Map<String, Object?> source) async {
    final active = _professions(source['professions']);
    final deleted = _professions(source['deleted_professions']);
    for (final key in {...active.keys, ...deleted.keys}) {
      groups[key] = _group(
        key,
        active[key] ?? deleted[key]!,
        deleted: deleted.containsKey(key),
      );
    }
    _readTargets(source['targets_v1']);
    final nextId = source['next_entry_id'];
    if (nextId != null && (nextId is! int || nextId <= 0)) {
      issue('invalid_next_id', blocks: true);
    }
    final rawRows = source['entries_json_list'] ?? const [];
    if (rawRows is! List) {
      issue('invalid_record_list', blocks: true);
      return;
    }
    sourceRecordCount = rawRows.length;
    for (final (ordinal, rawRow) in rawRows.indexed) {
      await _readRecord(rawRow, ordinal);
    }
    if (nextId is int && seenIds.any((id) => id >= nextId)) {
      issue('legacy_counter_overlaps_existing_id');
    }
  }

  Map<String, String> _professions(Object? value) {
    final result = <String, String>{};
    if (value == null) return result;
    if (value is! List) {
      issue('invalid_profession_list', blocks: true);
      return result;
    }
    for (final label in value) {
      if (label is! String || label.trim().isEmpty) {
        issue('invalid_profession_name', blocks: true);
        continue;
      }
      final key = _normalise(label);
      final existing = result.putIfAbsent(key, () => label);
      if (existing != label) issue('normalised_profession_alias');
    }
    return result;
  }

  _Group _group(String key, String label, {required bool deleted}) =>
      _Group(_stableId([sourceId, 'group', key]), label, deleted: deleted);

  void _readTargets(Object? rawTargets) {
    if (rawTargets == null || rawTargets == '') return;
    final data = _decodeMap(rawTargets);
    if (data == null) {
      issue('invalid_targets', blocks: true);
      return;
    }
    final seen = <String>{};
    for (final entry in data.entries) {
      final key = _normalise(entry.key);
      final group = groups[key];
      final target = entry.value;
      if (group == null ||
          target is! Map ||
          target['minutes'] is! int ||
          (target['minutes'] as int) < 0 ||
          !const ['week', 'month', 'year'].contains(target['cycle'])) {
        issue('unresolved_target', blocks: true);
        continue;
      }
      if (!seen.add(key)) {
        issue('conflicting_target_aliases', blocks: true);
        continue;
      }
      targets[group.id] = {
        'minutes': target['minutes'] as int,
        'cycle': target['cycle'] as String,
      };
    }
  }

  Future<void> _readRecord(Object? rawRow, int ordinal) async {
    final row = _decodeMap(rawRow);
    if (row == null) {
      issue('invalid_record_json', blocks: true, row: ordinal);
      return;
    }
    final legacyId = row['id'];
    final profession = row['profession'];
    final day = _legacyDay(row['date']);
    final title = row['title'] ?? '';
    final details = row['details'] ?? '';
    final hours = row['hours'] ?? 0;
    final minutes = row['minutes'] ?? 0;
    final deleted = row['deleted'] ?? false;
    final links = row['attachments'] ?? const [];
    if (legacyId is! int ||
        profession is! String ||
        profession.trim().isEmpty ||
        day == null ||
        title is! String ||
        details is! String ||
        hours is! int ||
        hours < 0 ||
        hours > (0x7fffffffffffffff - 59) ~/ 60 ||
        minutes is! int ||
        minutes < 0 ||
        minutes >= 60 ||
        deleted is! bool ||
        links is! List ||
        links.any((link) => link is! String)) {
      issue('ambiguous_record_values', blocks: true, row: ordinal);
      return;
    }
    if (row.keys.any((key) => !_knownRecordKeys.contains(key))) {
      issue('unknown_record_fields_retained', row: ordinal);
    }
    if (!seenIds.add(legacyId)) issue('duplicate_legacy_id', row: ordinal);
    final key = _normalise(profession);
    final group = groups.putIfAbsent(key, () {
      issue('orphan_profession_retained', row: ordinal);
      return _group(key, profession, deleted: true);
    });
    final id = _stableId([sourceId, 'row', ordinal]);
    final evidence = <String>[];
    for (final (index, reference) in links.cast<String>().indexed) {
      final attachment = await _attachment(id, index, reference, ordinal);
      evidence.add(attachment.id);
      attachments.add(attachment);
    }
    records.add(
      RecordingRecord(
        id: id,
        collectionId: group.id,
        layoutVersion: 1,
        version: 1,
        deleted: deleted,
        values: {
          group.field('cpd.activityDate'): day,
          group.field('cpd.title'): title,
          group.field('cpd.details'): details,
          group.field('cpd.creditedDuration'): hours * 60 + minutes,
          if (evidence.isNotEmpty) group.field('cpd.evidence'): evidence,
        },
      ),
    );
    recordMapping.add({'row': ordinal, 'legacyId': legacyId, 'id': id});
  }

  Future<RecordingAttachment> _attachment(
    String recordId,
    int index,
    String reference,
    int ordinal,
  ) async {
    final id = _stableId([recordId, 'attachment', index]);
    final uri = Uri.tryParse(reference.trim());
    if (uri != null &&
        (const ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty ||
            const ['mailto', 'tel'].contains(uri.scheme) &&
                uri.path.isNotEmpty)) {
      return RecordingAttachment(
        id: id,
        kind: AttachmentKind.link,
        locator: reference,
        name: 'Link',
      );
    }
    final candidate = _relativeDocumentPath(reference, originals.root.path);
    final name = p.basename(reference).trim();
    if (candidate != null) {
      final managed = RecordingAttachment(
        id: id,
        kind: AttachmentKind.managed,
        locator: candidate,
        name: name.isEmpty ? 'Attachment' : name,
      );
      try {
        final file = await originals.resolveOriginal(managed);
        if (file != null &&
            p.isWithin(
              p.join(
                await originals.root.resolveSymbolicLinks(),
                'attachments',
              ),
              file.path,
            )) {
          fingerprints[id] = await _fileFingerprint(file);
          return managed;
        }
      } on FileSystemException {
        issue('unreadable_attachment', row: ordinal, attachment: index);
      }
    }
    issue('unresolved_attachment', row: ordinal, attachment: index);
    return RecordingAttachment(
      id: id,
      kind: AttachmentKind.unresolved,
      locator: reference,
      name: name.isEmpty ? 'Attachment' : name,
    );
  }
}

Map<String, Object?>? _decodeMap(Object? raw) {
  if (raw is! String) return null;
  try {
    final value = jsonDecode(raw);
    return value is Map<String, dynamic> && !_hasRepeatedJsonKeys(raw)
        ? value.cast<String, Object?>()
        : null;
  } on FormatException {
    return null;
  }
}

/// The standard decoder keeps the last value for a repeated object key.
/// Scan already-validated JSON so an earlier value cannot silently disappear.
bool _hasRepeatedJsonKeys(String json) {
  final containers = <Set<String>?>[];
  final tokens = RegExp(r'[{}\[\]]|"(?:[^"\\]|\\.)*"[ \t\r\n]*:?');
  for (final match in tokens.allMatches(json)) {
    final token = match.group(0)!;
    switch (token) {
      case '{':
        containers.add({});
      case '[':
        containers.add(null);
      case '}' || ']':
        containers.removeLast();
      default:
        if (token.endsWith(':')) {
          final key =
              jsonDecode(token.substring(0, token.length - 1)) as String;
          if (!containers.last!.add(key)) return true;
        }
    }
  }
  return false;
}

String? _legacyDay(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
    r'^([0-9]{4}-[0-9]{2}-[0-9]{2})(?:T00:00:00(?:\.0{3,6})?)?$',
  ).firstMatch(value);
  if (match == null || match.end != value.length) return null;
  final day = match.group(1)!;
  return isCalendarDay(day) ? day : null;
}

String? _relativeDocumentPath(String reference, String directory) {
  if (reference.isEmpty ||
      reference.contains(r'\') ||
      reference.contains(':') ||
      reference.contains('\u0000') ||
      reference.split('/').any((part) => part == '.' || part == '..')) {
    return null;
  }
  var candidate = reference;
  if (p.isAbsolute(reference)) {
    if (p.isWithin(directory, reference)) {
      candidate = p.relative(reference, from: directory);
    } else {
      // An old iOS container can be rebased only into the evidence directory.
      const marker = '/Documents/attachments/';
      final offset = reference.indexOf(marker);
      if (offset < 0) return null;
      candidate = reference.substring(offset + '/Documents/'.length);
    }
  }
  final segments = candidate.split('/');
  if (segments.length < 2 ||
      segments.first != 'attachments' ||
      segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return candidate;
}

/// A deterministic content fingerprint for recovery verification. UUID v5
/// digests fixed-size chunks so large evidence files are read with bounded I/O.
Future<String> _fileFingerprint(File file) async {
  final reader = await file.open();
  try {
    const chunkSize = 64 * 1024;
    var fingerprint = Namespace.url.value;
    var length = 0;
    while (true) {
      final bytes = await reader.read(chunkSize);
      if (bytes.isEmpty) break;
      length += bytes.length;
      fingerprint = _uuid.v5FromBytes(fingerprint, bytes);
    }
    return '$length:$fingerprint';
  } finally {
    await reader.close();
  }
}
