import 'package:path/path.dart' as p;

import '../models.dart';
import '../recording_engine/models.dart';
import '../recording_engine_storage/managed_attachment_files.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import '../utils/attachment_io.dart';
import '../utils/record_search.dart';
import 'cpd_layout_policy.dart';
import 'report_locale.dart';

typedef CpdProfessionItem = ({String id, String label, bool deleted});

class CpdRecordItem {
  const CpdRecordItem({
    required this.id,
    required this.professionId,
    required this.entry,
    this.version = 0,
    this.evidence = const [],
    this.additionalSearchText = const [],
  });

  factory CpdRecordItem.legacy(CpdEntry entry, {String? professionId}) =>
      CpdRecordItem(
        id: entry.id.toString(),
        professionId: professionId ?? entry.profession,
        entry: entry,
      );

  final String id;
  final String professionId;
  final int version;
  final CpdEntry entry;
  final List<CpdEvidenceItem> evidence;
  final List<String> additionalSearchText;

  bool matches(String query) {
    if (RecordSearch.matches(entry, query)) return true;
    final needle = query.trim().toLowerCase();
    return additionalSearchText.any(
      (value) => value.toLowerCase().contains(needle),
    );
  }
}

class CpdEvidenceItem {
  const CpdEvidenceItem({
    required this.id,
    required this.fieldId,
    required this.ordinal,
    required this.label,
    required this.target,
  });

  final String id;
  final String fieldId;
  final int ordinal;
  final String label;
  final String? target;
}

/// The optional CPD browsing and management contract for a recording workspace.
abstract interface class CpdRecordsSource {
  Future<List<CpdProfessionItem>> professions();
  Future<List<CpdRecordItem>> records({
    String? professionId,
    bool deleted = false,
  });
  Future<void> setDeleted(
    CpdRecordItem item,
    bool deleted, {
    bool recoverProfession = false,
  });
  Future<void> unlinkEvidence(
    String recordId,
    int version,
    CpdEvidenceItem evidence,
  );
  Future<Map<String, String>> preferences();
  Future<void> setReportLanguage(ReportLanguage language);
}

class SqliteCpdRecordsSource implements CpdRecordsSource {
  const SqliteCpdRecordsSource(
    this.repository,
    this.originals, {
    required Future<Map<String, String>> Function() preferences,
    required Future<void> Function(ReportLanguage) setReportLanguage,
  }) : _preferences = preferences,
       _saveReportLanguage = setReportLanguage;

  final SqliteRecordingRepository repository;
  final ManagedAttachmentFiles originals;

  final Future<Map<String, String>> Function() _preferences;
  final Future<void> Function(ReportLanguage) _saveReportLanguage;

  @override
  Future<Map<String, String>> preferences() => _preferences();

  @override
  Future<void> setReportLanguage(ReportLanguage language) =>
      _saveReportLanguage(language);

  @override
  Future<List<CpdProfessionItem>> professions() async => [
    for (final group in await repository.loadCollections())
      (id: group.id, label: group.label, deleted: group.deleted),
  ];

  @override
  Future<List<CpdRecordItem>> records({
    String? professionId,
    bool deleted = false,
  }) => repository.transaction((tx) async {
    final rows = <CpdRecordItem>[];
    final attachments = <String, RecordingAttachment?>{};
    for (final group in await tx.loadCollections()) {
      if (professionId != null && group.id != professionId) continue;
      if (group.deleted && !deleted) continue;
      final records = await tx.loadRecords(group.id, includeDeleted: deleted);
      final selected = records.where((record) => record.deleted == deleted);
      if (selected.isEmpty) continue;
      final layouts = await tx.loadLayouts(group.id);
      for (final record in selected) {
        final fields = resolveFields(record.layoutVersion, layouts);
        final bindings = cpdFieldBindings(fields);
        final evidence = <CpdEvidenceItem>[];
        final exportTargets = <String>[];
        final searchable = <String>[];
        for (final field in fields) {
          final value = record.values[field.id];
          if (value == null) continue;
          if (field.definition.kind != FieldKind.attachments) {
            searchable.add(field.definition.displayValue(value).toString());
            continue;
          }
          for (final (ordinal, id) in (value as List).cast<String>().indexed) {
            if (!attachments.containsKey(id)) {
              attachments[id] = await tx.loadAttachment(id);
            }
            final asset = attachments[id];
            if (asset == null) {
              throw StateError('Evidence metadata is missing.');
            }
            final link =
                asset.kind == AttachmentKind.link && isUrl(asset.locator);
            final target = link
                ? asset.locator
                : (await originals.resolveOriginal(asset))?.path;
            final name = asset.name;
            evidence.add(
              CpdEvidenceItem(
                id: id,
                fieldId: field.id,
                ordinal: ordinal,
                label: link ? asset.locator : name,
                target: target,
              ),
            );
            searchable.addAll([name, if (link) asset.locator]);
            exportTargets.add(
              target ??
                  p.join(
                    originals.root.path,
                    'unavailable-$id',
                    p.basename(name),
                  ),
            );
          }
        }
        final minutes =
            record.values[bindings['cpd.creditedDuration']] as int? ?? 0;
        rows.add(
          CpdRecordItem(
            id: record.id,
            professionId: group.id,
            version: record.version,
            evidence: List.unmodifiable(evidence),
            additionalSearchText: List.unmodifiable(searchable),
            entry: CpdEntry(
              // A tie-breaker for the legacy exporter. Mutations use the UUID.
              id: rows.length,
              profession: group.label,
              date: DateTime.parse(
                record.values[bindings['cpd.activityDate']] as String,
              ),
              title: record.values[bindings['cpd.title']] as String? ?? '',
              details: record.values[bindings['cpd.details']] as String? ?? '',
              hours: minutes ~/ 60,
              minutes: minutes % 60,
              attachments: List.unmodifiable(exportTargets),
              deleted: record.deleted,
            ),
          ),
        );
      }
    }
    return rows;
  });

  @override
  Future<void> setDeleted(
    CpdRecordItem item,
    bool deleted, {
    bool recoverProfession = false,
  }) => repository.transaction((tx) async {
    if (!deleted && recoverProfession) {
      await tx.updateCollection(item.professionId, deleted: false);
    }
    await tx.setRecordDeleted(item.id, deleted, expectedVersion: item.version);
  });

  @override
  Future<void> unlinkEvidence(
    String recordId,
    int version,
    CpdEvidenceItem evidence,
  ) => repository.transaction((tx) async {
    final record = await tx.loadRecord(recordId);
    final ids = (record?.values[evidence.fieldId] as List?)?.cast<String>();
    if (ids == null ||
        evidence.ordinal >= ids.length ||
        ids[evidence.ordinal] != evidence.id) {
      throw StateError('Evidence changed. Reopen the record to try again.');
    }
    final remaining = List<String>.of(ids)..removeAt(evidence.ordinal);
    await tx.updateValues(recordId, {
      evidence.fieldId: remaining.isEmpty ? null : remaining,
    }, expectedVersion: version);
    // Link removal does not reclaim originals, including shared evidence.
  });
}
