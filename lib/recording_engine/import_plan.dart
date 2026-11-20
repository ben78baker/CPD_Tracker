import 'models.dart';

enum ImportStatus { captured, blocked, staged, verified }

/// The host supplies a lossless source snapshot and a deterministic projection.
/// Metadata is opaque to the repository and can include source-row mappings and
/// diagnostics. Neither a staged nor a verified import activates a database.
class RecordingImportPlan {
  RecordingImportPlan({
    required this.sourceId,
    required this.rawSnapshot,
    required this.metadata,
    required this.blocked,
    required Iterable<RecordingCollection> collections,
    required Iterable<LayoutRevision> layouts,
    required Iterable<RecordingRecord> records,
    required Iterable<RecordingAttachment> attachments,
  }) : collections = List.unmodifiable(collections),
       layouts = List.unmodifiable(layouts),
       records = List.unmodifiable(records),
       attachments = List.unmodifiable(attachments);

  final String sourceId;
  final String rawSnapshot;
  final String metadata;
  final bool blocked;
  final List<RecordingCollection> collections;
  final List<LayoutRevision> layouts;
  final List<RecordingRecord> records;
  final List<RecordingAttachment> attachments;
}

class ImportSnapshot {
  const ImportSnapshot({
    required this.raw,
    required this.status,
    this.metadata,
    this.verifiedAt,
  });

  final String raw;
  final ImportStatus status;
  final String? metadata;
  final DateTime? verifiedAt;
}
