import 'dart:convert';

enum MigrationPhase {
  disabled,
  checkingStorage,
  snapshotReady,
  staging,
  verifying,
  reviewRequired,
  ready,
  rehearsalActivated,
  productionActivated,
  failed,
}

enum RecoveryDisposition { preserved, requiresResolution }

class RecoveryIssue {
  const RecoveryIssue(this.code, this.disposition, {this.row, this.attachment});

  final String code;
  final RecoveryDisposition disposition;
  final int? row;
  final int? attachment;

  factory RecoveryIssue.fromPlanner(Map item) {
    final code = item['code'] as String;
    final manual =
        item['blocks'] == true ||
        const {
          'duplicate_legacy_id',
          'normalised_profession_alias',
          'unsupported_evidence_reference',
          'unreadable_attachment',
        }.contains(code);
    return RecoveryIssue(
      code,
      manual
          ? RecoveryDisposition.requiresResolution
          : RecoveryDisposition.preserved,
      row: item['row'] as int?,
      attachment: item['attachment'] as int?,
    );
  }

  factory RecoveryIssue.fromJson(Map item) => RecoveryIssue(
    item['code'] as String,
    RecoveryDisposition.values.byName(item['disposition'] as String),
    row: item['row'] as int?,
    attachment: item['attachment'] as int?,
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'disposition': disposition.name,
    'row': ?row,
    'attachment': ?attachment,
  };
}

class MigrationReport {
  const MigrationReport(
    this.phase, {
    this.sourceId,
    this.failure,
    this.requiredBytes,
    this.availableBytes,
    this.review = const [],
  });

  final MigrationPhase phase;
  final String? sourceId;
  final String? failure;
  final int? requiredBytes;
  final int? availableBytes;
  final List<RecoveryIssue> review;

  factory MigrationReport.decode(String raw) {
    final value = jsonDecode(raw) as Map;
    return MigrationReport(
      MigrationPhase.values.byName(value['phase'] as String),
      sourceId: value['sourceId'] as String?,
      failure: value['failure'] as String?,
      requiredBytes: value['requiredBytes'] as int?,
      availableBytes: value['availableBytes'] as int?,
      review: (value['review'] as List)
          .map((item) => RecoveryIssue.fromJson(item as Map))
          .toList(),
    );
  }

  String encode() => jsonEncode({
    'phase': phase.name,
    'sourceId': ?sourceId,
    'failure': ?failure,
    'requiredBytes': ?requiredBytes,
    'availableBytes': ?availableBytes,
    'review': review.map((issue) => issue.toJson()).toList(),
  });
}
