import 'dart:io';

import 'package:cpd_tracker/cpd_backup/cpd_collection_backup.dart';
import 'package:cpd_tracker/cpd_creation/historical_bundles.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/original_directory_sync.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'phase6_rehearsal_app.dart' show phase6Store;
import 'phase7_rehearsal_app.dart' show seedPhase7;

const password = 'CPD rehearsal password · Δ';

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Native rehearsal only.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('Profession backup verification')),
    ),
  );
  final root = await Directory.systemTemp.createTemp('profession-native-');
  try {
    final documents = await getApplicationDocumentsDirectory();
    final mode = File(p.join(documents.path, 'pb-command'));
    if (await mode.exists()) {
      await _interruption(documents, await mode.readAsString());
      return;
    }
    final incoming = [
      for (final mode in ['plain', 'locked'])
        File(p.join(documents.path, 'pb-in-$mode.recordingbackup')),
    ];
    if (await incoming.first.exists() && await incoming.last.exists()) {
      for (final (i, source) in incoming.indexed) {
        final workspace = await _workspace(root, 'cross-$i');
        final db = await _open(workspace);
        try {
          await _verifyRestoration(
            root,
            cpdCollectionBackup(availableDeviceStorage),
            source,
            workspace,
            db,
            inputPassword: i == 0 ? null : password,
            protocols: false,
          );
        } finally {
          await db.close();
        }
      }
      await _signal(documents, 'PB_CROSS_PASS');
      return;
    }
    await _run(root, documents);
    await _signal(documents, 'PB_NATIVE_PASS');
  } catch (error, stack) {
    debugPrintSynchronously('PB_NATIVE_FAIL $error\n$stack');
    rethrow;
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> _run(Directory root, Directory documents) async {
  final left = await _workspace(root, 'source');
  final right = await _workspace(root, 'destination');
  final src = await _open(left);
  final dest = await _open(right);
  final service = cpdCollectionBackup(availableDeviceStorage);
  final originals = _files(left);
  try {
    final (chosen, other) = await seedPhase7(phase6Store(src), left.originals);
    await src.saveHostValue(cpdCollectionTargets, chosen, '840:year');
    await src.saveHostValue(cpdCollectionTargets, other, '1200:month');
    final records = await src.loadRecords(chosen);
    final layout = (await src.loadLayouts(chosen)).last;
    final evidence = layout.fields.firstWhere(
      (field) => field.definition.kind == FieldKind.attachments,
    );
    final image = File(p.join(root.path, 'sample.jpg'));
    final handle = await image.open(mode: FileMode.writeOnly);
    try {
      await handle.truncate(8 * 1024 * 1024);
      await handle.flush();
    } finally {
      await handle.close();
    }
    final files = [
      for (final name in [
        'Large photo.jpg',
        'Missing certificate.pdf',
        'Damaged document.pdf',
      ])
        await originals.copyOriginal(image, displayName: name),
    ];
    final record = await src.createRecord(
      chosen,
      {
        ...records.first.values,
        evidence.id: files.map((item) => item.id).toList(),
      },
      expectedLayoutVersion: layout.version,
      newAttachments: files,
    );
    await src.setRecordDeleted(
      record.id,
      true,
      expectedVersion: record.version,
    );
    await (await originals.resolveOriginal(files[1]))!.delete();
    await (await originals.resolveOriginal(
      files[2],
    ))!.writeAsString('changed evidence', flush: true);

    final timer = Stopwatch()..start();
    final draft = await service.create(
      repository: src,
      collectionId: chosen,
      originals: left.originals,
      temporary: root,
    );
    final createMs = timer.elapsedMilliseconds;
    _check(draft.summary.deletedRecords == 1, 'deleted record included');
    _check(
      draft.summary.unavailable.any(
            (e) => e.reason == UnavailableOriginal.missing,
          ) &&
          draft.summary.unavailable.any(
            (e) => e.reason == UnavailableOriginal.damaged,
          ),
      'missing and damaged originals declared',
    );
    await _expectFailure(draft.fileForSharing, BackupProblem.integrity);
    await _expectStatus(
      await service.restore(
        review: await service.inspect(
          source: await draft.fileForSharing(acceptUnavailable: true),
          temporary: root,
        ),
        repository: src,
        originals: originals,
        label: 'Renamed original',
      ),
      CollectionImportStatus.existing,
    );
    final plain = File(p.join(documents.path, 'pb-out-plain.recordingbackup'));
    final locked = File(
      p.join(documents.path, 'pb-out-locked.recordingbackup'),
    );
    timer.reset();
    await (await draft.fileForSharing(
      password: password,
      acceptUnavailable: true,
    )).copy(locked.path);
    final encryptMs = timer.elapsedMilliseconds;
    await (await draft.fileForSharing(
      acceptUnavailable: true,
    )).copy(plain.path);
    await draft.dispose();
    final archived = await PortableArchive().inspect(plain);
    final bad = await locked.copy(p.join(root.path, 'bad-lock'));
    final data = await bad.open(mode: FileMode.append);
    await data.writeByte(0);
    await data.close();
    await _expectFailure(
      () => service.inspect(
        source: locked,
        temporary: root,
        password: 'incorrect passphrase',
      ),
      BackupProblem.authentication,
    );
    await _expectFailure(
      () => service.inspect(source: bad, temporary: root, password: password),
      BackupProblem.authentication,
    );
    final damaged = await plain.copy(p.join(root.path, 'bad-plain'));
    final change = await damaged.open(mode: FileMode.append);
    await change.setPosition(await damaged.length() - 1);
    await change.writeByte(1);
    await change.close();
    await _expectFailure(
      () => service.inspect(source: damaged, temporary: root),
      BackupProblem.integrity,
    );

    timer.reset();
    await _verifyRestoration(
      root,
      service,
      locked,
      right,
      dest,
      inputPassword: password,
      protocols: true,
    );
    await _signal(
      documents,
      'PB_SCALE backup_ms=$createMs encrypt_ms=$encryptMs '
      'restore_checks_ms=${timer.elapsedMilliseconds} plain=${await plain.length()} '
      'encrypted=${await locked.length()} records=${records.length + 1} '
      'evidence=${archived.originals} rss=${ProcessInfo.currentRss}',
    );
  } finally {
    await src.close();
    await dest.close();
  }
}

Future<void> _verifyRestoration(
  Directory root,
  SqliteCollectionBackup service,
  File file,
  RecordingWorkspace dest,
  SqliteRecordingRepository db, {
  String? inputPassword,
  required bool protocols,
}) async {
  final unrelated = await db.createCollection('Unrelated existing profession');
  final sourceBytes = await backupDigest(file);
  final timer = Stopwatch()..start();
  final review = await service.inspect(
    source: file,
    temporary: root,
    password: inputPassword,
  );
  final inspectMs = timer.elapsedMilliseconds;
  try {
    final originals = _files(dest);
    Future<CollectionImportResult> restore({
      String name = 'Restored nursing',
      Future<void> Function()? interrupt,
    }) => service.restore(
      review: review,
      repository: db,
      originals: originals,
      label: name,
      beforeCommit: interrupt,
    );
    if (protocols) {
      final low = cpdCollectionBackup((_) async => 1024);
      await _expectFailure(
        () => low.restore(
          review: review,
          repository: db,
          originals: originals,
          label: 'Low',
        ),
        BackupProblem.capacity,
      );
      await _expectStatus(
        await restore(name: unrelated.label),
        CollectionImportStatus.nameInUse,
      );
      try {
        await restore(
          interrupt: () async => throw const FormatException('Interrupted'),
        );
        throw StateError('Restore unexpectedly succeeded');
      } on FormatException {
        _check(
          (await db.loadCollections()).length == 1,
          'Transaction rolled back',
        );
      }
    }
    timer.reset();
    final added = await restore();
    final restoreMs = timer.elapsedMilliseconds;
    await _expectStatus(added, CollectionImportStatus.added);
    final collection = added.collection!;
    _check(
      (await db.loadCollections())
          .map((item) => item.id)
          .contains(unrelated.id),
      'unrelated profession retained',
    );
    _check(
      (await db.loadRecords(collection.id, includeDeleted: true)).length ==
          review.summary.recordCount,
      'complete records',
    );
    _check(
      review.summary.unavailable.length >= 2,
      'residual evidence metadata',
    );
    final periods = await SchemePeriodStore(db).load(collection.id);
    final chosen = periods.periods.firstWhere((p) => p.id == periods.selected);
    final bundle = await const HistoricalCpdBundles().read(
      db,
      chosen.templateId,
      chosen.templateVersion,
      chosen.ruleVersion,
    );
    _check(
      bundle?.encode() == nursingBundle.encode(),
      'pinned historical rules retained',
    );
    _check(
      (await db.loadHostState(cpdCollectionTargets))[collection.id] ==
          '840:year',
      'target retained',
    );
    final store = phase6Store(db);
    _check(
      await store.purchaseStates().then((values) => values.isEmpty),
      'grants stay local',
    );
    _check(
      !await store.canAddToLayout((await db.loadLayouts(collection.id)).last),
      'unverified template cannot create records',
    );
    final activeLayout = (await db.loadLayouts(collection.id)).last;
    var blocked = false;
    try {
      await store.createActivity(
        collection.id,
        {},
        expectedLayoutVersion: activeLayout.version,
      );
    } on StateError {
      blocked = true;
    }
    _check(
      blocked,
      'paid recording action rejects missing ownership at commit',
    );
    _check(
      (await db.loadRecords(collection.id)).isNotEmpty,
      'historical records accessible',
    );
    _check(
      await backupDigest(file) == sourceBytes,
      'provider file left intact',
    );
    if (protocols) {
      await _expectStatus(
        await restore(name: 'Another name'),
        CollectionImportStatus.existing,
      );
      final reexported = await service.create(
        repository: db,
        collectionId: collection.id,
        originals: originals.root,
        temporary: root,
      );
      try {
        final second = await service.inspect(
          source: await reexported.fileForSharing(acceptUnavailable: true),
          temporary: root,
        );
        try {
          await _expectStatus(
            await service.restore(
              review: second,
              repository: db,
              originals: originals,
              label: 'Different export',
            ),
            CollectionImportStatus.existing,
          );
        } finally {
          await second.dispose();
        }
      } finally {
        await reexported.dispose();
      }
      await db.updateCollection(collection.id, deleted: true);
      await _expectStatus(await restore(), CollectionImportStatus.recoverable);
      await service.purgeDeletedCollection(db, collection.id);
      final repeated = await restore();
      await _expectStatus(repeated, CollectionImportStatus.added);
      _check(
        repeated.collection!.id != collection.id,
        'new internal identity after purge',
      );
    }
    debugPrintSynchronously(
      'PB_RESTORED inspect_ms=$inspectMs commit_ms=$restoreMs '
      'encrypted=${inputPassword != null} records=${review.summary.recordCount}',
    );
  } finally {
    await review.dispose();
  }
}

Future<void> _interruption(Directory documents, String mode) async {
  final root = await Directory(p.join(documents.path, 'pb-process')).create();
  final work = await _workspace(root, 'live');
  final db = await _open(work);
  final engine = cpdCollectionBackup(availableDeviceStorage);
  final originals = _files(work);
  final archive = File(p.join(documents.path, 'pb-out-plain.recordingbackup'));
  try {
    if (mode == 'kill') {
      await db.createCollection('Existing acknowledged profession');
    } else {
      _check(
        (await db.loadCollections()).length == 1,
        'No partial import after process exit',
      );
      await engine.reconcileInterruptedRestores(db, originals.root);
      final pending = Directory(
        p.join(originals.root.path, ManagedAttachmentFiles.restoredOriginals),
      );
      _check(
        !await pending.exists() || await pending.list().isEmpty,
        'Uncommitted originals reconciled',
      );
    }
    final review = await engine.inspect(source: archive, temporary: root);
    try {
      final restored = await engine.restore(
        review: review,
        repository: db,
        originals: originals,
        label: 'Restarted import',
        beforeCommit: mode != 'kill'
            ? null
            : () async {
                await _signal(documents, 'PB_KILL_READY');
                await Future<void>.delayed(const Duration(minutes: 4));
                throw StateError(
                  'The external launcher did not terminate this process.',
                );
              },
      );
      _check(
        restored.status == CollectionImportStatus.added,
        'Retry completes once',
      );
      _check(
        (await db.loadCollections()).length == 2,
        'Only the intended tile added',
      );
      await _signal(documents, 'PB_RESTART_PASS');
    } finally {
      await review.dispose();
    }
  } finally {
    await db.close();
  }
}

Future<void> _signal(Directory documents, String message) async {
  await File(
    p.join(documents.path, 'pb-status'),
  ).writeAsString('$message\n', mode: FileMode.append, flush: true);
  debugPrintSynchronously(message);
}

Future<RecordingWorkspace> _workspace(Directory root, String name) async {
  final result = RecordingWorkspace(Directory(p.join(root.path, name)));
  await result.originals.create(recursive: true);
  return result;
}

ManagedAttachmentFiles _files(RecordingWorkspace work) =>
    ManagedAttachmentFiles(
      work.originals,
      syncDirectory: syncOriginalDirectory,
    );
Future<SqliteRecordingRepository> _open(RecordingWorkspace work) =>
    SqliteRecordingRepository.open(work.databasePath, durableWrites: true);

void _check(bool okay, String problem) {
  if (!okay) throw StateError(problem);
}

Future<void> _expectFailure(
  Future<Object?> Function() run,
  BackupProblem problem,
) async {
  try {
    await run();
  } on BackupException catch (failure) {
    _check(failure.problem == problem, 'Unexpected failure $failure');
    return;
  }
  throw StateError('Expected $problem');
}

Future<void> _expectStatus(
  CollectionImportResult result,
  CollectionImportStatus status,
) async =>
    _check(result.status == status, 'Expected $status, got ${result.status}');
