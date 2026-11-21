import 'dart:convert';

enum RecoveryRetention {
  keepUntilActivation,
  keepUntilIntegrityConfirmed,
  keepUntilReviewResolved,
  keepForMinimumPeriod,
  eligibleForManualReview,
}

/// Stored with the destination authority marker in SQLite.
class MigrationReceipt {
  const MigrationReceipt({
    required this.sourceId,
    required this.snapshotFingerprint,
    required this.verifiedAt,
    required this.activatedAt,
    required this.rehearsal,
    this.bindingId,
  });

  final String sourceId;
  final String snapshotFingerprint;
  final DateTime verifiedAt;
  final DateTime activatedAt;
  final bool rehearsal;
  final String? bindingId;

  static const minimumRetention = Duration(days: 30);
  DateTime get retainUntil => activatedAt.toUtc().add(minimumRetention);

  factory MigrationReceipt.decode(String raw) {
    final value = jsonDecode(raw) as Map;
    return MigrationReceipt(
      sourceId: value['sourceId'] as String,
      snapshotFingerprint: value['snapshotFingerprint'] as String,
      verifiedAt: DateTime.parse(value['verifiedAt'] as String),
      activatedAt: DateTime.parse(value['activatedAt'] as String),
      rehearsal: value['rehearsal'] as bool,
      bindingId: value['bindingId'] as String?,
    );
  }

  String encode() => jsonEncode({
    'sourceId': sourceId,
    'snapshotFingerprint': snapshotFingerprint,
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    'activatedAt': activatedAt.toUtc().toIso8601String(),
    'rehearsal': rehearsal,
    'bindingId': ?bindingId,
  });
}

RecoveryRetention recoveryRetention({
  required MigrationReceipt? receipt,
  required DateTime now,
  required bool integrityConfirmed,
  required bool unresolved,
}) {
  if (receipt == null) return RecoveryRetention.keepUntilActivation;
  if (!integrityConfirmed || receipt.activatedAt.isBefore(receipt.verifiedAt)) {
    return RecoveryRetention.keepUntilIntegrityConfirmed;
  }
  if (unresolved) return RecoveryRetention.keepUntilReviewResolved;
  if (now.toUtc().isBefore(receipt.retainUntil)) {
    return RecoveryRetention.keepForMinimumPeriod;
  }
  return RecoveryRetention.eligibleForManualReview;
}
