import 'dart:convert';

import '../recording_engine/models.dart';
import '../recording_engine_storage/managed_attachment_files.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'scheme_progress.dart';
import 'template_bundle.dart';

/// CPD host metadata. A collection owns its selection and its immutable period
/// history. Selecting a period or creating another never edits prior bounds.
class SchemePeriodStore {
  const SchemePeriodStore(this.repository);
  final SqliteRecordingRepository repository;

  static String namespace(String id) => 'cpd.scheme.periods:$id';

  Future<({String? selected, List<SchemePeriod> periods})> load(
    String collectionId,
  ) async {
    final state = await repository.loadHostState(namespace(collectionId));
    return (
      selected: state['selected'],
      periods: [
        for (final row in state.entries)
          if (row.key.startsWith('period:'))
            SchemePeriod.fromJson(
              jsonDecode(row.value) as Map<String, dynamic>,
            ),
      ]..sort((a, b) => b.end.compareTo(a.end)),
    );
  }

  Future<void> select(String collectionId, SchemePeriod period) =>
      repository.transaction((tx) async {
        final collection = await tx.loadCollection(collectionId);
        final history = await tx.loadLayouts(collectionId);
        if (collection == null ||
            collection.deleted ||
            !history.any(
              (layout) =>
                  layout.templateId == period.templateId &&
                  layout.templateVersion == period.templateVersion,
            )) {
          throw StateError(
            'The period must belong to a template adopted by this profession.',
          );
        }
        final periodNamespace = namespace(collectionId);
        final state = await tx.loadHostState(periodNamespace);
        final key = 'period:${period.id}';
        final data = jsonEncode(period.toJson());
        if (state[key] case final previous?) {
          if (previous != data) {
            throw StateError('A retained period is immutable.');
          }
        } else {
          await tx.saveHostValue(periodNamespace, key, data);
        }
        await tx.saveHostValue(periodNamespace, 'selected', period.id);
      });
}

typedef SchemeEvidence = ({String name, bool available, String? url});

Future<
  ({
    SchemeProgress progress,
    Map<String, LayoutField> bindings,
    Map<String, SchemeEvidence> evidence,
  })
>
loadSchemeProgress({
  required SqliteRecordingRepository repository,
  required ProfessionTemplateBundle bundle,
  required SchemePeriod period,
  required List<LayoutRevision> history,
  required List<RecordingRecord> records,
  ManagedAttachmentFiles? originals,
}) async {
  final baseline = history.firstWhere(
    (revision) =>
        revision.templateVersion == period.templateVersion &&
        revision.templateId == bundle.recipe.id,
  );
  if (records.any((record) => record.collectionId != baseline.collectionId)) {
    throw StateError(
      'The report must use records from the selected profession.',
    );
  }
  final bindings = adoptedRecipeFields(bundle, baseline);
  final resolved = <SchemeActivity>[];
  final evidence = <String, SchemeEvidence>{};
  for (final record in records.where((record) => !record.deleted)) {
    final fields = resolveFields(record.layoutVersion, history);
    resolved.add(SchemeActivity(record.id, fields, record.values));
    for (final field in fields.where(
      (field) => field.definition.kind == FieldKind.attachments,
    )) {
      if (record.values[field.id] case final List refs) {
        for (final ref in refs.whereType<String>()) {
          if (evidence.containsKey(ref)) continue;
          final attachment = await repository.loadAttachment(ref);
          final locator = Uri.tryParse(attachment?.locator ?? '');
          final url =
              attachment?.kind == AttachmentKind.link &&
                  locator != null &&
                  locator.host.isNotEmpty &&
                  (locator.scheme == 'https' || locator.scheme == 'http')
              ? attachment!.locator
              : null;
          evidence[ref] = (
            name: attachment?.name ?? ref,
            available:
                url != null ||
                (attachment?.kind == AttachmentKind.managed &&
                    await originals?.resolveOriginal(attachment!) != null),
            url: url,
          );
        }
      }
    }
  }
  return (
    progress: calculateSchemeProgress(
      bundle: bundle,
      period: period,
      activities: resolved,
      adoptedFields: bindings,
      availableEvidence: evidence.entries
          .where((item) => item.value.available)
          .map((item) => item.key)
          .toSet(),
    ),
    bindings: bindings,
    evidence: Map<String, SchemeEvidence>.unmodifiable(evidence),
  );
}
