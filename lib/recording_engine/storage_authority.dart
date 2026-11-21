import 'dart:convert';

enum StoreAuthority { legacy, recording, recovery }

enum AuthorityScope { production, rehearsal }

enum ArtifactState { absent, valid, invalid }

enum RecoveryCopyState { absent, manifestVerified, damaged, unchecked }

enum AuthorityReason {
  newInstallation,
  legacyInstallation,
  interruptedStaging,
  verifiedStaging,
  abandonedStaging,
  activated,
  damagedJournal,
  invalidFence,
  invalidDatabase,
  invalidReceipt,
  missingDestination,
  interruptedHandoff,
  inconsistentEvidence,
  unsupportedDatabase,
}

/// Independent, write-once evidence that a handoff has begun. The same binding
/// must be committed in the destination before a writer may start.
class AuthorityBinding {
  AuthorityBinding({
    required this.id,
    required this.sourceId,
    required this.snapshotFingerprint,
    required this.scope,
  }) {
    if ([
      id,
      sourceId,
      snapshotFingerprint,
    ].any((value) => value.trim().isEmpty)) {
      throw const FormatException('Incomplete authority binding.');
    }
  }

  final String id;
  final String sourceId;
  final String snapshotFingerprint;
  final AuthorityScope scope;

  factory AuthorityBinding.decode(String raw) {
    final data = jsonDecode(raw) as Map;
    if (data['version'] != 1) {
      throw const FormatException('Unknown authority version.');
    }
    return AuthorityBinding(
      id: data['id'] as String,
      sourceId: data['sourceId'] as String,
      snapshotFingerprint: data['snapshotFingerprint'] as String,
      scope: AuthorityScope.values.byName(data['scope'] as String),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'id': id,
    'sourceId': sourceId,
    'snapshotFingerprint': snapshotFingerprint,
    'scope': scope.name,
  });

  bool matches(AuthorityBinding other) =>
      id == other.id &&
      sourceId == other.sourceId &&
      snapshotFingerprint == other.snapshotFingerprint &&
      scope == other.scope;
}

class StartupAuthorityEvidence {
  const StartupAuthorityEvidence({
    this.scope = AuthorityScope.production,
    this.hasLegacyRecords = false,
    this.hasAttempt = false,
    this.stageVerified = false,
    this.stageAbandoned = false,
    this.journalValid = true,
    this.journalClaimsActivation = false,
    this.fenceState = ArtifactState.absent,
    this.fence,
    this.databaseState = ArtifactState.absent,
    this.databaseVersionSupported = true,
    this.receiptState = ArtifactState.absent,
    this.receipt,
    this.destinationMatches = false,
    this.recoveryCopy = RecoveryCopyState.unchecked,
  });

  final AuthorityScope scope;
  final bool hasLegacyRecords;
  final bool hasAttempt;
  final bool stageVerified;
  final bool stageAbandoned;
  final bool journalValid;
  final bool journalClaimsActivation;
  final ArtifactState fenceState;
  final AuthorityBinding? fence;
  final ArtifactState databaseState;
  final bool databaseVersionSupported;
  final ArtifactState receiptState;
  final AuthorityBinding? receipt;
  final bool destinationMatches;
  final RecoveryCopyState recoveryCopy;
}

class StartupAuthority {
  const StartupAuthority(this.store, this.reason, this.recoveryCopy);
  final StoreAuthority store;
  final AuthorityReason reason;
  final RecoveryCopyState recoveryCopy;
}

/// Selects at most one writer. Once any evidence of activation exists,
/// uncertainty stops both writers instead of reopening a stale source.
StartupAuthority resolveStartupAuthority(StartupAuthorityEvidence evidence) {
  StartupAuthority result(StoreAuthority store, AuthorityReason reason) =>
      StartupAuthority(store, reason, evidence.recoveryCopy);
  StartupAuthority stop(AuthorityReason reason) =>
      result(StoreAuthority.recovery, reason);

  if (evidence.fenceState == ArtifactState.invalid) {
    return stop(AuthorityReason.invalidFence);
  }
  if (evidence.databaseState == ArtifactState.invalid) {
    return stop(AuthorityReason.invalidDatabase);
  }
  if (!evidence.databaseVersionSupported) {
    return stop(AuthorityReason.unsupportedDatabase);
  }
  if (evidence.receiptState == ArtifactState.invalid) {
    return stop(AuthorityReason.invalidReceipt);
  }
  if ((evidence.fence != null) !=
          (evidence.fenceState == ArtifactState.valid) ||
      (evidence.receipt != null) !=
          (evidence.receiptState == ArtifactState.valid)) {
    return stop(AuthorityReason.inconsistentEvidence);
  }

  final fence = evidence.fence;
  final receipt = evidence.receipt;
  if (fence != null || receipt != null || evidence.journalClaimsActivation) {
    if (evidence.databaseState == ArtifactState.absent) {
      return stop(AuthorityReason.missingDestination);
    }
    if (fence != null && receipt == null && fence.scope == evidence.scope) {
      return stop(AuthorityReason.interruptedHandoff);
    }
    if (fence == null ||
        receipt == null ||
        fence.scope != evidence.scope ||
        !fence.matches(receipt) ||
        !evidence.destinationMatches) {
      return stop(AuthorityReason.inconsistentEvidence);
    }
    // The live store and its independent fence establish authority. Recovery
    // media and the old progress journal have their own health status.
    return result(StoreAuthority.recording, AuthorityReason.activated);
  }
  if (!evidence.journalValid) return stop(AuthorityReason.damagedJournal);
  if (evidence.stageAbandoned) {
    return result(StoreAuthority.legacy, AuthorityReason.abandonedStaging);
  }
  if (evidence.stageVerified) {
    if (evidence.databaseState == ArtifactState.absent) {
      return stop(AuthorityReason.missingDestination);
    }
    return result(StoreAuthority.legacy, AuthorityReason.verifiedStaging);
  }
  if (evidence.hasAttempt) {
    return result(StoreAuthority.legacy, AuthorityReason.interruptedStaging);
  }
  if (evidence.databaseState != ArtifactState.absent) {
    return stop(AuthorityReason.inconsistentEvidence);
  }
  return result(
    StoreAuthority.legacy,
    evidence.hasLegacyRecords
        ? AuthorityReason.legacyInstallation
        : AuthorityReason.newInstallation,
  );
}

enum StartupRecoveryAction {
  retryStaging,
  abandonStaging,
  copyLegacySnapshot,
  preserveRecordingStore,
}

/// A legacy snapshot may be opened in isolation even when current data is
/// unsafe. It is never an active-store replacement.
Set<StartupRecoveryAction> recoveryActions(StartupAuthority state) => {
  if (state.store == StoreAuthority.legacy &&
      (state.reason == AuthorityReason.interruptedStaging ||
          state.reason == AuthorityReason.verifiedStaging)) ...{
    StartupRecoveryAction.retryStaging,
    StartupRecoveryAction.abandonStaging,
  },
  if (state.recoveryCopy == RecoveryCopyState.manifestVerified)
    StartupRecoveryAction.copyLegacySnapshot,
  if (state.store != StoreAuthority.legacy)
    StartupRecoveryAction.preserveRecordingStore,
};
