import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_backup/cpd_portable_backup.dart';
import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_creation/historical_bundles.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_rehearsal_page.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/recording_engine_storage/protected_recording_store.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cpd_migration/native_rehearsal_media.dart' show RehearsalMedia;
import '../cpd_migration/phase3b_rehearsal_app.dart'
    show openSyntheticRehearsal;
import 'equipment_fixture.dart';
import 'phase6_rehearsal_app.dart' show phase6Store;
import 'phase7_rehearsal_app.dart' show seedPhase7;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(home: Scaffold(body: Text('Phase 8 native backup'))),
  );
  try {
    final documents = await getApplicationDocumentsDirectory();
    final command = File(p.join(documents.path, 'phase8-command'));
    final mode = await command.exists()
        ? (await command.readAsString()).trim()
        : '';
    final current = Directory(p.join(documents.path, 'phase8-kill-rehearsal'));
    if (mode == 'kill' || mode == 'recover') {
      await _termination(current, mode);
      return;
    }
    final sandbox = await Directory.systemTemp.createTemp('phase8_native_');
    try {
      final incoming = File(
        p.join(documents.path, 'phase8-incoming.recordingbackup'),
      );
      if (await incoming.exists()) {
        await _import(incoming, sandbox);
        debugPrintSynchronously('PHASE8_TRANSFER_PASS');
        return;
      }
      await _equipment(sandbox);
      await _cpd(sandbox, documents);
      await _migratedLegacy(sandbox);
      await _scale(sandbox);
      debugPrintSynchronously('PHASE8_NATIVE_PASS');
    } finally {
      await sandbox.delete(recursive: true);
    }
  } catch (error, stack) {
    debugPrintSynchronously('PHASE8_NATIVE_FAIL $error\n$stack');
    rethrow;
  }
}

void _require(bool check, String message) {
  if (!check) throw StateError(message);
}

Future<void> _blocked(Future<Object?> Function() attempt) async {
  try {
    await attempt();
  } catch (_) {
    return;
  }
  throw StateError('An unsafe operation completed.');
}

Future<RecordingWorkspace> _work(Directory root, String name) async {
  final work = RecordingWorkspace(Directory(p.join(root.path, name)));
  await work.originals.create(recursive: true);
  return work;
}

Future<void> _equipment(Directory root) async {
  final work = await _work(root, 'equipment');
  final archive = SqliteRecordingBackup(available: availableDeviceStorage);
  final store = ProtectedRecordingStore(
    live: work,
    recovery: Directory(p.join(root.path, 'equipment-receipts')),
    backup: archive,
  );
  final repo = await SqliteRecordingRepository.open(work.databasePath);
  final recipe = equipmentTemplate(1);
  await repo.saveTemplate(recipe);
  final collection = await repo.createCollection('Plant room');
  final layout = await repo.applyTemplate(
    collection.id,
    recipe,
    expectedVersion: 1,
  );
  String field(String key) =>
      layout.fields[recipe.fields.indexWhere((field) => field.id == key)].id;
  await repo.close();
  await store.enrol();
  final fixture = await File(
    p.join(root.path, 'manual.pdf'),
  ).writeAsString('%PDF-1.4 fixture');
  final record = await store.write((db, files) async {
    final original = await files.copyOriginal(fixture);
    return db.createRecord(
      collection.id,
      {
        field('asset'): 'A-012',
        field('result'): 'monitor',
        field('evidence'): [original.id],
      },
      expectedLayoutVersion: layout.version,
      newAttachments: [original],
    );
  });
  final attachmentId =
      (record.values[field('evidence')] as List).single as String;
  await store.write((db, _) async {
    await db.saveTemplate(equipmentTemplate(2));
    await db.setRecordDeleted(record.id, true, expectedVersion: record.version);
    await db.updateCollection(collection.id, deleted: true);
  });
  final healthy = await store.verifyCurrent();
  _require(healthy.originals == 1, 'Original referenced by deleted data');
  final read = await SqliteRecordingRepository.open(work.databasePath);
  final original = await read.loadAttachment(attachmentId);
  await read.close();
  final file = (await ManagedAttachmentFiles(
    work.originals,
  ).resolveOriginal(original!))!;
  await file.writeAsString('tampered', flush: true);
  await _blocked(store.verifyCurrent);
  // Damage the live database as well. The independent acknowledged copy
  // must recover both the most recent delete and the original evidence.
  await File(work.databasePath).writeAsString('damaged database', flush: true);
  final saved = await store.recoverAcknowledged(
    Directory(p.join(root.path, 'equipment-recovered')),
  );
  final restored = await SqliteRecordingRepository.open(saved.databasePath);
  try {
    _require(
      (await restored.loadCollection(collection.id))!.deleted,
      'Deleted collection',
    );
    final item = await restored.loadRecord(record.id);
    _require(
      item!.deleted && item.values[field('result')] == 'monitor',
      'Historical record',
    );
    final evidence = await restored.loadAttachment(attachmentId);
    final original = await ManagedAttachmentFiles(
      saved.originals,
    ).resolveOriginal(evidence!);
    _require(
      await original!.readAsString() == '%PDF-1.4 fixture',
      'Exact evidence after corruption',
    );
    _require(
      (await restored.loadTemplate(recipe.id, 2))!.version == 2,
      'New template',
    );
  } finally {
    await restored.close();
  }
}

Future<void> _cpd(Directory root, Directory documents) async {
  final work = await _work(root, 'cpd');
  final backup = cpdPortableBackup(availableDeviceStorage);
  final repo = await SqliteRecordingRepository.open(work.databasePath);
  final store = phase6Store(repo);
  final result = await seedPhase7(store, work.originals);
  final media = await RehearsalMedia.create(root);
  for (final source in [media.photo, media.pdf]) {
    final files = ManagedAttachmentFiles(work.originals);
    await repo.saveAttachment(await files.copyOriginal(source));
  }
  await store.saveSetting('locale', 'es');
  await store.saveSetting('reportLocale', 'fr');
  final output = File(
    p.join(documents.path, 'phase8-outgoing.recordingbackup'),
  );
  if (await output.exists()) await output.delete();
  try {
    await backup.create(
      repository: repo,
      originals: work.originals,
      destination: output,
    );
    final lowSpace = SqliteRecordingBackup(available: (_) async => 0);
    final inspection = await backup.inspect(output);
    final blocked = Directory(p.join(root.path, 'blocked-restore'));
    await _blocked(
      () => lowSpace.restore(
        source: output,
        inspection: inspection,
        destination: blocked,
      ),
    );
    _require(!await blocked.exists(), 'Low capacity never publishes a restore');
    final originalDir = Directory(
      p.join(work.originals.path, 'recording_originals'),
    );
    final original = await originalDir
        .list()
        .where((file) => file is File)
        .first;
    await original.delete();
    final missingOutput = File(p.join(root.path, 'missing.recordingbackup'));
    await _blocked(
      () => backup.create(
        repository: repo,
        originals: work.originals,
        destination: missingOutput,
      ),
    );
    _require(
      !await missingOutput.exists(),
      'Missing evidence never produces success',
    );
  } finally {
    await repo.close();
  }
  await _import(output, root, ids: [result.$1, result.$2]);
  await _validateMalicious(output, root);
}

Future<void> _import(File source, Directory root, {List<String>? ids}) async {
  final backup = cpdPortableBackup(availableDeviceStorage);
  final inspection = await backup.inspect(source);
  final restored = await backup.restore(
    source: source,
    inspection: inspection,
    destination: Directory(p.join(root.path, 'restored-cpd')),
  );
  final repo = await SqliteRecordingRepository.open(restored.databasePath);
  try {
    final collections = await repo.loadCollections();
    _require(collections.length == 3 && inspection.originals == 3, 'Coverage');
    final professions = collections.skip(1).toList();
    if (ids != null) {
      _require(
        listEquals(professions.map((item) => item.id).toList(), ids),
        'Exact placement identities',
      );
    }
    for (final profession in professions) {
      final periods = await SchemePeriodStore(repo).load(profession.id);
      final selected = periods.periods.singleWhere(
        (item) => item.id == periods.selected,
      );
      // No installed catalogue supplied during historical lookup.
      final rules = await const HistoricalCpdBundles().read(
        repo,
        selected.templateId,
        selected.templateVersion,
        selected.ruleVersion,
      );
      _require(
        rules?.encode() == nursingBundle.encode(),
        'Retained reporting rules',
      );
    }
    _require(
      (await phase6Store(repo).settings())['reportLocale'] == 'fr',
      'Host preferences',
    );
    _require(
      (await phase6Store(repo).settings())['locale'] == 'es',
      'Independent app locale',
    );
    _require(
      (await repo.loadHostState('cpd.creation.grants')).isEmpty,
      'Grants excluded',
    );
    debugPrintSynchronously(
      'PHASE8_ARCHIVE ${inspection.seal} ${await source.length()} bytes',
    );
  } finally {
    await repo.close();
  }
}

Future<void> _validateMalicious(File source, Directory root) async {
  const container = PortableArchive();
  final backup = cpdPortableBackup(availableDeviceStorage);
  final staged = await root.createTemp('copy-for-adversarial-test-');
  final incoming = await backup.inspect(source);
  await container.extract(
    source,
    staged,
    available: availableDeviceStorage,
    expectedSeal: incoming.seal,
  );
  final payload = File(p.join(staged.path, PortableArchive.rows));
  final inputs = {
    for (final entry in incoming.entries)
      entry.path: File(p.join(staged.path, entry.path)),
  };
  final rows = await payload.readAsLines();
  final target = rows.indexWhere((row) => row.startsWith('["records",'));
  final invalid = File(p.join(root.path, 'duplicate-record.recordingbackup'));
  await payload.writeAsString(
    '${[...rows.take(target), rows[target], ...rows.skip(target)].join('\n')}\n',
  );
  final checked = await container.write(
    files: inputs,
    destination: invalid,
    created: DateTime.now(),
    schema: incoming.schema,
    available: availableDeviceStorage,
  );
  final duplicate = Directory(p.join(root.path, 'duplicate-data'));
  await _blocked(
    () => backup.restore(
      source: invalid,
      inspection: checked,
      destination: duplicate,
    ),
  );
  _require(
    !await duplicate.exists(),
    'Duplicate identities never publish the candidate',
  );

  final forged = File(p.join(root.path, 'forged-grant.recordingbackup'));
  await payload.writeAsString(
    '${[
      jsonEncode([
        'host_state',
        {'namespace': 'cpd.creation.grants', 'key': 'legacy', 'value': 'verified'},
      ]),
      ...rows,
    ].join('\n')}\n',
  );
  final forgedHeader = await container.write(
    files: inputs,
    destination: forged,
    created: DateTime.now(),
    schema: incoming.schema,
    available: availableDeviceStorage,
  );
  final installed = await backup.restore(
    source: forged,
    inspection: forgedHeader,
    destination: Directory(p.join(root.path, 'sanitised')),
  );
  final db = await SqliteRecordingRepository.open(installed.databasePath);
  try {
    _require(
      (await db.loadHostState('cpd.creation.grants')).isEmpty,
      'Forged grant removed',
    );
  } finally {
    await db.close();
  }
  debugPrintSynchronously('PHASE8_ADVERSARIAL_PASS');
}

Future<void> _migratedLegacy(Directory root) async {
  final attempt = await openSyntheticRehearsal(
    RehearsalSample.standard,
    (_) async {},
  );
  final portable = cpdPortableBackup(availableDeviceStorage);
  try {
    final result = await attempt.rehearse();
    _require(
      result.phase == MigrationPhase.ready,
      'Legacy rehearsal verified before packaging',
    );
    final sourceId = result.sourceId!;
    final original = await SqliteRecordingRepository.open(attempt.databasePath);
    final file = File(p.join(root.path, 'legacy-portable.recordingbackup'));
    final BackupInspection inspection;
    try {
      inspection = await portable.create(
        repository: original,
        originals: attempt.documents,
        destination: file,
      );
    } finally {
      await original.close();
    }
    final staged = await portable.restore(
      source: file,
      inspection: inspection,
      destination: Directory(p.join(root.path, 'verified-legacy')),
    );
    final db = await SqliteRecordingRepository.open(staged.databasePath);
    try {
      final restored = await SqliteCpdStore.openVerified(
        db,
        sourceId: sourceId,
        documents: staged.originals,
      );
      await restored.verifyLegacyProjection(await attempt.readLegacy());
      _require(
        inspection.originals == 1,
        'Legacy original preserved along with missing reference',
      );
    } finally {
      await db.close();
    }
    debugPrintSynchronously('PHASE8_LEGACY_PORTABLE_PASS');
  } finally {
    await attempt.workspace.parent.delete(recursive: true);
  }
}

Future<void> _scale(Directory root) async {
  final live = await _work(root, 'scale');
  final db = await SqliteRecordingRepository.open(live.databasePath);
  final archive = SqliteRecordingBackup(available: availableDeviceStorage);
  final fields = equipmentTemplate(1).fields;
  final image = await File(
    p.join(root.path, 'large.jpg'),
  ).open(mode: FileMode.writeOnly);
  try {
    await image.truncate(1024 * 1024);
    await image.flush();
  } finally {
    await image.close();
  }
  int peakRss = ProcessInfo.currentRss;
  final stop = Stopwatch()..start();
  try {
    for (var group = 0; group < 8; group++) {
      final profession = await db.createCollection(
        'Workshop $group',
        fields: fields,
      );
      await db.transaction((tx) async {
        for (var index = 0; index < 250; index++) {
          RecordingAttachment? original;
          if (index % 40 == 0) {
            original = await ManagedAttachmentFiles(
              live.originals,
            ).copyOriginal(File(p.join(root.path, 'large.jpg')));
          }
          await tx.createRecord(
            profession.id,
            {
              'asset': 'Workshop $group / serial $index',
              'result': 'pass',
              'notes': 'Fixed replacement part. ' * 8,
              if (original != null) 'evidence': [original.id],
            },
            expectedLayoutVersion: 1,
            newAttachments: [?original],
          );
        }
      });
    }
    final seedMs = stop.elapsedMilliseconds;
    stop.reset();
    final output = File(p.join(root.path, 'scale.recordingbackup'));
    final inspection = await archive.create(
      repository: db,
      originals: live.originals,
      destination: output,
    );
    peakRss = peakRss < ProcessInfo.currentRss
        ? ProcessInfo.currentRss
        : peakRss;
    final createMs = stop.elapsedMilliseconds;
    stop.reset();
    final restored = await archive.restore(
      source: output,
      inspection: inspection,
      destination: Directory(p.join(root.path, 'scale-restored')),
    );
    peakRss = peakRss < ProcessInfo.currentRss
        ? ProcessInfo.currentRss
        : peakRss;
    final restoreMs = stop.elapsedMilliseconds;
    final verified = await SqliteRecordingRepository.open(
      restored.databasePath,
    );
    try {
      _require(
        (await verified.loadAllRecords()).length == 2000,
        'Scale record count',
      );
    } finally {
      await verified.close();
    }
    debugPrintSynchronously(
      'PHASE8_SCALE seed_ms=$seedMs create_ms=$createMs restore_ms=$restoreMs '
      'archive_bytes=${await output.length()} sqlite_bytes=${await File(live.databasePath).length()} '
      'originals=${inspection.originals} rss_after_phases=$peakRss',
    );
  } finally {
    await db.close();
  }
}

Future<void> _termination(Directory root, String mode) async {
  final live = RecordingWorkspace(Directory(p.join(root.path, 'live')));
  final archive = SqliteRecordingBackup(available: availableDeviceStorage);
  final store = ProtectedRecordingStore(
    live: live,
    recovery: Directory(p.join(root.path, 'receipts')),
    backup: archive,
    onStage: mode == 'kill'
        ? (stage) async {
            if (stage == ProtectedWriteStage.committed) {
              debugPrintSynchronously('PHASE8_KILL_NOW');
              await Future<void>.delayed(const Duration(minutes: 5));
            }
          }
        : null,
  );
  if (mode == 'kill') {
    await live.originals.create(recursive: true);
    final db = await SqliteRecordingRepository.open(live.databasePath);
    await db.createCollection('Acknowledged data');
    await db.close();
    await store.enrol();
    await store.write(
      (db, _) => db.createCollection('Committed before interruption'),
    );
    return;
  }
  await _blocked(store.verifyCurrent);
  final copy = await store.recoverAcknowledged(
    Directory(p.join(root.path, 'review')),
  );
  final db = await SqliteRecordingRepository.open(copy.databasePath);
  final interrupted = await SqliteRecordingRepository.open(live.databasePath);
  try {
    _require(
      (await db.loadCollections()).single.label == 'Acknowledged data',
      'Last confirmed data',
    );
    _require(
      (await interrupted.loadCollections()).length == 2,
      'Newer live data preserved',
    );
    debugPrintSynchronously('PHASE8_PROCESS_RECOVERY_PASS');
  } finally {
    await db.close();
    await interrupted.close();
  }
}
