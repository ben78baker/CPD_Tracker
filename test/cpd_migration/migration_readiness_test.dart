import 'dart:async';
import 'dart:io';

import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/recovery_retention.dart';
import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'freeze drains in-flight composite writes and rejects new writes',
    () async {
      final gate = LegacyWriteGate();
      final admitted = Completer<void>();
      final resume = Completer<void>();
      final writes = <String>[];
      final inflight = gate.write(() async {
        admitted.complete();
        await resume.future;
        await gate.write(() async => writes.add('nested existing writer'));
        writes.add('outer writer finished');
      });
      await admitted.future;
      final freeze = gate.freeze(() async => writes.add('exclusive migration'));
      await expectLater(
        gate.write(() async => writes.add('unexpected')),
        throwsStateError,
      );
      await expectLater(
        gate.freeze(() async => writes.add('unexpected')),
        throwsStateError,
      );
      expect(writes, isEmpty);
      resume.complete();
      await inflight;
      await freeze;
      await gate.write(() async => writes.add('legacy resumed'));
      expect(writes, [
        'nested existing writer',
        'outer writer finished',
        'exclusive migration',
        'legacy resumed',
      ]);
    },
  );

  test(
    'legacy writers refuse during a freeze and resume after failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'professions': ['Dentistry'],
      });
      final settings = SettingsStore.instance;
      final repo = EntryRepository();
      final gate = LegacyWriteGate.instance;
      await expectLater(
        gate.freeze(() async {
          await expectLater(
            settings.renameProfession('Dentistry', 'New label'),
            throwsStateError,
          );
          await expectLater(
            settings.setTarget('Dentistry', minutes: 30, cycle: 'week'),
            throwsStateError,
          );
          await expectLater(
            settings.loadDeletedProfessions(),
            throwsStateError,
          );
          await expectLater(
            repo.createAndSave(
              profession: 'Dentistry',
              date: DateTime(2024, 1, 1),
              title: 'Sample',
              details: '',
              hours: 0,
              minutes: 5,
              attachments: [],
            ),
            throwsStateError,
          );
          expect(await repo.loadAll(), isEmpty);
          throw StateError('synthetic failure');
        }),
        throwsStateError,
      );
      expect(await settings.loadProfessions(), ['Dentistry']);
      expect(await settings.getTarget('Dentistry'), isNull);
      await settings.setTarget('Dentistry', minutes: 30, cycle: 'week');
      expect(await settings.getTarget('Dentistry'), (30, 'week'));
    },
  );

  test(
    'production seal requires an exclusive freeze and stays closed',
    () async {
      final gate = LegacyWriteGate();
      expect(gate.seal, throwsStateError);
      await gate.freeze(() async => gate.seal());
      await expectLater(gate.write(() async {}), throwsStateError);
    },
  );

  test(
    'activation is disabled before paths, capacity or legacy data are touched',
    () async {
      final scratch = await Directory.systemTemp.createTemp('cpd_disabled_');
      addTearDown(() => scratch.delete(recursive: true));
      final coordinator = CpdMigrationCoordinator(
        workspace: Directory(p.join(scratch.path, 'absent')),
        documents: Directory(p.join(scratch.path, 'absent-source')),
        readLegacy: () async => fail('would read legacy'),
        availableStorage: (_) async => fail('would measure capacity'),
      );
      expect(coordinator.productionActivationEnabled, isFalse);
      expect(
        (await coordinator.activateProduction()).phase,
        MigrationPhase.disabled,
      );
      expect(await scratch.list().isEmpty, isTrue);
    },
  );

  test(
    'capacity preflight retains the legacy source and creates no database or snapshot',
    () async {
      final scratch = await Directory.systemTemp.createTemp('cpd_capacity_');
      addTearDown(() => scratch.delete(recursive: true));
      final documents = await Directory(
        p.join(scratch.path, 'Documents'),
      ).create();
      final attachment = File(
        p.join(documents.path, 'attachments', 'proof.pdf'),
      );
      await attachment.parent.create();
      await attachment.writeAsBytes([1, 2, 3]);
      final workspace = Directory(p.join(scratch.path, 'preflight'));
      final gate = LegacyWriteGate();
      final coordinator = CpdMigrationCoordinator(
        workspace: workspace,
        documents: documents,
        readLegacy: () async => {'entries_json_list': <String>[]},
        availableStorage: (_) async => 100,
        gate: gate,
      );
      final result = await coordinator.rehearse();
      expect(result.phase, MigrationPhase.failed);
      expect(result.failure, 'insufficient_storage');
      expect(result.availableBytes, 100);
      expect(result.requiredBytes, greaterThan(100));
      expect(await File(coordinator.databasePath).exists(), isFalse);
      expect(await coordinator.snapshot.directory.exists(), isFalse);
      expect(await attachment.readAsBytes(), [1, 2, 3]);
      expect((await coordinator.lastReport())?.failure, result.failure);
      expect(await gate.write(() async => 'resumed'), 'resumed');
    },
  );

  test('a second coordinator cannot enter an in-flight attempt', () async {
    final root = await Directory.systemTemp.createTemp('cpd_concurrency_');
    addTearDown(() => root.delete(recursive: true));
    final docs = await Directory(p.join(root.path, 'Documents')).create();
    final workspace = Directory(p.join(root.path, 'attempt'));
    final measured = Completer<void>();
    final release = Completer<int>();
    CpdMigrationCoordinator attempt() => CpdMigrationCoordinator(
      workspace: workspace,
      documents: docs,
      gate: LegacyWriteGate(),
      readLegacy: () async => {},
      availableStorage: (_) {
        measured.complete();
        return release.future;
      },
    );
    final first = attempt().rehearse();
    await measured.future;
    try {
      await expectLater(attempt().rehearse(), throwsStateError);
    } finally {
      release.complete(0);
    }
    expect((await first).failure, 'insufficient_storage');
  });

  test('rejects a workspace in Documents before creating it', () async {
    final docs = await Directory.systemTemp.createTemp('cpd_nested_attempt_');
    addTearDown(() => docs.delete(recursive: true));
    final workspace = Directory(p.join(docs.path, 'nested'));
    final coordinator = CpdMigrationCoordinator(
      workspace: workspace,
      documents: docs,
      readLegacy: () async => fail('would read legacy'),
    );
    await expectLater(coordinator.rehearse(), throwsArgumentError);
    expect(await workspace.exists(), isFalse);
  });

  test(
    'retention starts at activation and holds incomplete, uncertain or unresolved copies',
    () {
      final activation = DateTime.utc(2026, 1, 12);
      final receipt = MigrationReceipt(
        sourceId: 'fixture',
        snapshotFingerprint: 'fingerprint',
        rehearsal: true,
        verifiedAt: activation.subtract(const Duration(days: 10)),
        activatedAt: activation,
      );
      RecoveryRetention policy(
        DateTime day, {
        bool integrity = true,
        bool unresolved = false,
        bool activated = true,
      }) => recoveryRetention(
        receipt: activated ? receipt : null,
        now: day,
        integrityConfirmed: integrity,
        unresolved: unresolved,
      );
      expect(receipt.retainUntil, DateTime.utc(2026, 2, 11));
      expect(
        policy(activation.add(const Duration(days: 29, hours: 23))),
        RecoveryRetention.keepForMinimumPeriod,
      );
      expect(
        policy(receipt.retainUntil),
        RecoveryRetention.eligibleForManualReview,
      );
      expect(
        policy(receipt.retainUntil, integrity: false),
        RecoveryRetention.keepUntilIntegrityConfirmed,
      );
      expect(
        policy(receipt.retainUntil, unresolved: true),
        RecoveryRetention.keepUntilReviewResolved,
      );
      expect(
        policy(receipt.retainUntil, activated: false),
        RecoveryRetention.keepUntilActivation,
      );
      expect(
        MigrationReceipt.decode(receipt.encode()).retainUntil,
        receipt.retainUntil,
      );
    },
  );

  test('review reports expose identifiers but never raw values', () {
    const report = MigrationReport(
      MigrationPhase.reviewRequired,
      sourceId: 'fixture',
      review: [
        RecoveryIssue(
          'fractional_duration',
          RecoveryDisposition.requiresResolution,
          row: 5,
        ),
        RecoveryIssue(
          'unresolved_attachment',
          RecoveryDisposition.preserved,
          row: 9,
          attachment: 1,
        ),
      ],
    );
    final decoded = MigrationReport.decode(report.encode());
    expect(decoded.phase, report.phase);
    expect(decoded.review.map((issue) => issue.row), [5, 9]);
    expect(decoded.review.map((issue) => issue.disposition), [
      RecoveryDisposition.requiresResolution,
      RecoveryDisposition.preserved,
    ]);
    expect(decoded.review.last.attachment, 1);
  });
}
