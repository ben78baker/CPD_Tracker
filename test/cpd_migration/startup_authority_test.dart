import 'dart:io';

import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/startup_migration_authority.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/recovery_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final binding = AuthorityBinding(
  id: 'commit-1',
  sourceId: 'source-1',
  snapshotFingerprint: 'snapshot-1',
  scope: AuthorityScope.production,
);
final rehearsal = AuthorityBinding(
  id: binding.id,
  sourceId: binding.sourceId,
  snapshotFingerprint: binding.snapshotFingerprint,
  scope: AuthorityScope.rehearsal,
);

StartupAuthorityEvidence active({
  ArtifactState fenceState = ArtifactState.valid,
  ArtifactState receiptState = ArtifactState.valid,
  ArtifactState database = ArtifactState.valid,
  AuthorityBinding? fence,
  AuthorityBinding? receipt,
  bool matches = true,
  bool supported = true,
  bool journalValid = true,
  RecoveryCopyState recoveryCopy = RecoveryCopyState.manifestVerified,
}) => StartupAuthorityEvidence(
  fenceState: fenceState,
  fence: fenceState == ArtifactState.valid ? fence ?? binding : null,
  receiptState: receiptState,
  receipt: receiptState == ArtifactState.valid ? receipt ?? binding : null,
  databaseState: database,
  destinationMatches: matches,
  databaseVersionSupported: supported,
  journalValid: journalValid,
  recoveryCopy: recoveryCopy,
  hasLegacyRecords: true,
);

void main() {
  test('fresh and never-migrated installations retain their legacy writer', () {
    final fresh = resolveStartupAuthority(const StartupAuthorityEvidence());
    final existing = resolveStartupAuthority(
      const StartupAuthorityEvidence(hasLegacyRecords: true),
    );
    expect(fresh.store, StoreAuthority.legacy);
    expect(fresh.reason, AuthorityReason.newInstallation);
    expect(existing.store, StoreAuthority.legacy);
    expect(existing.reason, AuthorityReason.legacyInstallation);
  });

  test(
    'preflight interruption, verified staging and abandonment have one writer',
    () {
      final cases = {
        AuthorityReason.interruptedStaging: const StartupAuthorityEvidence(
          hasAttempt: true,
        ),
        AuthorityReason.verifiedStaging: const StartupAuthorityEvidence(
          hasAttempt: true,
          stageVerified: true,
          databaseState: ArtifactState.valid,
        ),
        AuthorityReason.abandonedStaging: const StartupAuthorityEvidence(
          hasAttempt: true,
          stageAbandoned: true,
          databaseState: ArtifactState.valid,
        ),
      };
      for (final entry in cases.entries) {
        final resolved = resolveStartupAuthority(entry.value);
        expect(resolved.store, StoreAuthority.legacy);
        expect(resolved.reason, entry.key);
      }
      expect(
        recoveryActions(resolveStartupAuthority(cases.values.last)),
        isNot(contains(StartupRecoveryAction.retryStaging)),
      );
    },
  );

  test(
    'bound SQLite remains authoritative across progress or recovery-copy damage',
    () {
      for (final state in RecoveryCopyState.values) {
        final result = resolveStartupAuthority(
          active(recoveryCopy: state, journalValid: false),
        );
        expect(result.store, StoreAuthority.recording);
        expect(result.recoveryCopy, state);
        expect(
          recoveryActions(result),
          isNot(contains(StartupRecoveryAction.abandonStaging)),
        );
      }
    },
  );

  test(
    'contradictory evidence never selects the potentially stale legacy store',
    () {
      final cases = [
        (
          active(fenceState: ArtifactState.absent),
          AuthorityReason.inconsistentEvidence,
        ),
        (
          active(fenceState: ArtifactState.invalid),
          AuthorityReason.invalidFence,
        ),
        (
          active(receiptState: ArtifactState.invalid),
          AuthorityReason.invalidReceipt,
        ),
        (
          active(receiptState: ArtifactState.absent),
          AuthorityReason.interruptedHandoff,
        ),
        (
          active(database: ArtifactState.absent),
          AuthorityReason.missingDestination,
        ),
        (
          active(database: ArtifactState.invalid),
          AuthorityReason.invalidDatabase,
        ),
        (active(supported: false), AuthorityReason.unsupportedDatabase),
        (active(matches: false), AuthorityReason.inconsistentEvidence),
        (
          active(fence: rehearsal, receipt: rehearsal),
          AuthorityReason.inconsistentEvidence,
        ),
        (active(receipt: rehearsal), AuthorityReason.inconsistentEvidence),
        (
          const StartupAuthorityEvidence(journalClaimsActivation: true),
          AuthorityReason.missingDestination,
        ),
        (
          const StartupAuthorityEvidence(stageVerified: true),
          AuthorityReason.missingDestination,
        ),
        (
          const StartupAuthorityEvidence(journalValid: false),
          AuthorityReason.damagedJournal,
        ),
      ];
      for (final (evidence, reason) in cases) {
        final result = resolveStartupAuthority(evidence);
        expect(result.store, StoreAuthority.recovery, reason: reason.name);
        expect(result.reason, reason);
        expect(
          recoveryActions(result),
          isNot(contains(StartupRecoveryAction.retryStaging)),
        );
      }
    },
  );

  test('contradictory marker state cannot claim a parsed receipt', () {
    final evidence = StartupAuthorityEvidence(
      databaseState: ArtifactState.valid,
      receipt: binding,
    );
    expect(resolveStartupAuthority(evidence).store, StoreAuthority.recovery);
  });

  test('wire identity survives encoding and rejects unknown versions', () {
    expect(AuthorityBinding.decode(binding.encode()).matches(binding), isTrue);
    expect(
      () => AuthorityBinding.decode('{"version":99}'),
      throwsFormatException,
    );
  });

  test(
    'an incomplete filesystem fence seals legacy writes before boot',
    () async {
      final root = await Directory.systemTemp.createTemp('cpd_authority_test_');
      addTearDown(() => root.delete(recursive: true));
      final startup = CpdStartupAuthority(
        Directory(p.join(root.path, 'attempt')),
      );
      await startup.fence.create(exclusive: true);
      final gate = LegacyWriteGate();
      final state = await startup.resolveAndGuard(
        gate,
        scope: AuthorityScope.production,
        hasLegacyRecords: true,
      );
      expect(state.store, StoreAuthority.recovery);
      await expectLater(
        gate.write(() async => fail('legacy writer ran')),
        throwsStateError,
      );
      expect(await startup.database.exists(), isFalse);
    },
  );

  test(
    'cold preservation includes sidecars, a fence and original evidence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cpd_preservation_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final current = await Directory(p.join(root.path, 'current')).create();
      final documents = await Directory(
        p.join(root.path, 'originals'),
      ).create();
      final database = await File(
        p.join(current.path, 'recording.sqlite'),
      ).writeAsBytes([0, 255]);
      await File('${database.path}-wal').writeAsBytes([1, 2]);
      await File(p.join(documents.path, 'proof.png')).writeAsBytes([9, 8]);
      final fence = await File(
        p.join(root.path, 'authority.json'),
      ).writeAsString(binding.encode());
      final destination = Directory(p.join(root.path, 'preserved'));
      await copyQuiescentRecordingFiles(
        database: database,
        fence: fence,
        destination: destination,
        originals: [documents],
      );
      expect(
        await File(p.join(destination.path, 'recording.sqlite')).readAsBytes(),
        [0, 255],
      );
      expect(
        await File(
          p.join(destination.path, 'recording.sqlite-wal'),
        ).readAsBytes(),
        [1, 2],
      );
      expect(
        await File(
          p.join(destination.path, 'originals', 'originals', 'proof.png'),
        ).readAsBytes(),
        [9, 8],
      );
      expect(await database.readAsBytes(), [0, 255]);
      await expectLater(
        copyQuiescentRecordingFiles(
          database: database,
          fence: fence,
          destination: destination,
        ),
        throwsStateError,
      );
    },
  );
}
