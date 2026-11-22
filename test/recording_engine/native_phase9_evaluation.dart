import 'dart:io';

import 'package:cpd_tracker/cpd_backup/cpd_collection_backup.dart';
import 'package:cpd_tracker/cpd_backup/cpd_portable_backup.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/original_directory_sync.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

const ledger = TemplateEvaluationLedger();
Future<int> _capacity(Directory _) async => 64 * 1024 * 1024;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('Phase 9 synthetic evaluation')),
    ),
  );
  final folder = await Directory.systemTemp.createTemp('phase9_evaluation_');
  try {
    await _verify(folder);
    debugPrintSynchronously('CPD_PHASE9_EVALUATION_PASS');
  } on Object catch (error, stack) {
    debugPrintSynchronously('CPD_PHASE9_EVALUATION_FAIL $error\n$stack');
    rethrow;
  } finally {
    await folder.delete(recursive: true);
  }
}

Future<void> _verify(Directory folder) async {
  final workspace = RecordingWorkspace(folder);
  final files = ManagedAttachmentFiles(
    workspace.originals,
    syncDirectory: syncOriginalDirectory,
  );
  final backup = cpdCollectionBackup(_capacity, evaluationLedger: ledger);
  var repository = await SqliteRecordingRepository.open(
    workspace.databasePath,
    durableWrites: true,
  );
  final pilot = nursingPilot;
  final updated = _recipe(pilot.id, 2);
  final independent = _recipe('fixture-independent', 1);
  ProfessionCreationStore host(SqliteRecordingRepository db) =>
      ProfessionCreationStore(
        db,
        templates: {
          (pilot.id, 1): pilot,
          (updated.id, 2): updated,
          (independent.id, 1): independent,
        },
        reportRules: {
          (pilot.id, 1): nursingReportRules,
          (updated.id, 2): nursingReportRules,
          (independent.id, 1): nursingReportRules,
        },
        bundles: {(pilot.id, 1): nursingBundle},
        evaluationLedger: ledger,
      );
  var store = host(repository);
  Future<String> place(String name, TemplateVersion recipe) async {
    final draft = (await store.begin(
      ProfessionKind.template,
      recipe: recipe,
    )).withChanges(name: name);
    await store.persist(draft);
    return store.commit(draft.id);
  }

  Future<RecordingRecord> add(
    String tile, {
    List<RecordingAttachment> evidence = const [],
  }) async {
    final layout = (await repository.loadLayouts(tile)).last;
    return store.createActivity(
      tile,
      _values(layout, evidence),
      expectedLayoutVersion: layout.version,
      newAttachments: evidence,
    );
  }

  try {
    await ledger.initialise(repository);
    await store.saveSetting('offline', 'true');
    _check(
      (await store.evaluationStatus(pilot.id)).used == 0,
      'fresh evaluation',
    );
    _check(
      !(await store.access()).canCustomiseFields,
      'evaluation has no app-wide grant',
    );
    final cancelled = await store.begin(ProfessionKind.template, recipe: pilot);
    await store.discard(cancelled.id);
    final first = await place('Hospital', pilot);
    final second = await place('Community', pilot);
    final third = await place('Agency', updated);
    final other = await place('Separate scheme', independent);
    final layout = (await repository.loadLayouts(first)).last;
    await _reject<ArgumentError>(
      () => store.createActivity(
        first,
        {},
        expectedLayoutVersion: layout.version,
      ),
    );
    _check(
      (await store.evaluationStatus(pilot.id)).used == 0,
      'invalid and cancelled requests are free',
    );

    final connection = await openDatabase(workspace.databasePath);
    await connection.execute(
      "CREATE TRIGGER abort_evaluation BEFORE INSERT ON host_state "
      "WHEN NEW.namespace = '${TemplateEvaluationLedger.namespace}' "
      "BEGIN SELECT RAISE(ABORT, 'synthetic accounting failure'); END",
    );
    await _reject<DatabaseException>(() => add(first));
    _check(
      (await repository.loadRecords(first)).isEmpty &&
          (await store.evaluationStatus(pilot.id)).used == 0,
      'failed ledger write rolls back inserted record',
    );
    await connection.execute('DROP TRIGGER abort_evaluation');

    final photo = File(p.join(folder.path, 'fixture.png'));
    await photo.writeAsBytes(
      image.encodePng(image.Image(width: 12, height: 12)),
    );
    final pdf = File(p.join(folder.path, 'fixture.pdf'));
    final sample = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Synthetic certificate')));
    await pdf.writeAsBytes(await sample.save());
    final evidence = [
      await files.copyOriginal(photo),
      await files.copyOriginal(pdf),
    ];
    final record = await add(first, evidence: evidence);
    _check(
      (await store.evaluationStatus(pilot.id)).used == 1,
      'first successful record',
    );
    final removed = await add(first);
    await repository.setRecordDeleted(
      removed.id,
      true,
      expectedVersion: removed.version,
    );
    await add(second);
    await add(second);
    _check(
      (await store.evaluationStatus(updated.id)).used == 4,
      'template v2 and two placements share count',
    );
    final racing = await Future.wait(
      [second, third].map((tile) async {
        try {
          await add(tile);
          return true;
        } on TemplateAllowanceException {
          return false;
        }
      }),
    );
    _check(
      racing.where((won) => won).length == 1,
      'fifth succeeds, simultaneous sixth fails',
    );
    await _reject<TemplateAllowanceException>(() => add(third));
    _check(
      (await store.evaluationStatus(pilot.id)).exhausted,
      'sixth refused across all tiles',
    );
    final extra = await place('Another placement', pilot);
    await _reject<TemplateAllowanceException>(() => add(extra));
    await add(other);
    _check(
      (await store.evaluationStatus(independent.id)).used == 1,
      'separate identity has separate allowance',
    );

    await repository.close();
    repository = await SqliteRecordingRepository.open(
      workspace.databasePath,
      durableWrites: true,
    );
    store = host(repository);
    _check(
      (await store.evaluationStatus(pilot.id)).exhausted,
      'usage survives restart offline',
    );
    await repository.updateCollection(second, deleted: true);
    await repository.updateCollection(second, deleted: false);
    _check(
      (await store.evaluationStatus(pilot.id)).exhausted,
      'profession deletion does not refill',
    );
    final method = _binding(layout, 'nmc.method');
    final edited = await repository.updateValues(record.id, {
      method: 'workshop',
    }, expectedVersion: record.version);
    _check(
      edited.values[method] == 'workshop' &&
          (await store.evaluationStatus(pilot.id)).exhausted,
      'existing record editable without another slot',
    );
    await store.requireOwnedReport(layout);
    await SchemePeriodStore(repository).select(first, rehearsalPeriod);
    final history = await repository.loadLayouts(first);
    final progress = await loadSchemeProgress(
      repository: repository,
      bundle: nursingBundle,
      period: rehearsalPeriod,
      history: history,
      records: [edited],
      originals: files,
    );
    final report = await buildSchemeReport(
      bundle: nursingBundle,
      progress: progress.progress,
      bindings: progress.bindings,
      evidence: progress.evidence,
      strings: AppLocalizationsEn(),
      practitioner: 'Sample',
    );
    _check(
      String.fromCharCodes(report.take(5)) == '%PDF-',
      'historical report still works',
    );
    _check(
      recordExportRows(
        edited,
        resolveFields(edited.layoutVersion, history),
      ).any((row) => row.last.contains('Workshop')),
      'CSV retains historical choice meaning',
    );

    final archive = await backup.create(
      repository: repository,
      collectionId: first,
      originals: files.root,
      temporary: folder,
    );
    try {
      final file = await archive.fileForSharing();
      final before = await backupDigest(file);
      final review = await backup.inspect(source: file, temporary: folder);
      try {
        final duplicate = await backup.restore(
          review: review,
          repository: repository,
          originals: files,
          label: 'Duplicate',
        );
        _check(
          duplicate.status == CollectionImportStatus.existing,
          'duplicate import is idempotent',
        );
        await repository.updateCollection(first, deleted: true);
        await backup.purgeDeletedCollection(repository, first);
        final restored = await backup.restore(
          review: review,
          repository: repository,
          originals: files,
          label: 'Hospital restored',
        );
        _check(
          restored.status == CollectionImportStatus.added &&
              (await store.evaluationStatus(pilot.id)).exhausted,
          'purge and restore does not refill cap',
        );
        final restoredId = restored.collection!.id;
        await _reject<TemplateAllowanceException>(() => add(restoredId));
        final saved = (await repository.loadRecords(restoredId)).single;
        final refs = (saved.values[_binding(layout, 'cpd.evidence')] as List)
            .cast<String>();
        final hashes = <String>{};
        for (final ref in refs) {
          final item = (await repository.loadAttachment(ref))!;
          hashes.add(await backupDigest((await files.resolveOriginal(item))!));
        }
        _check(
          hashes.length == 2 &&
              hashes.containsAll(
                evidence.map((item) => item.originalFingerprint),
              ),
          'photo and PDF originals preserved',
        );
        _check(
          saved.values[method] == 'workshop' &&
              await backupDigest(file) == before,
          'restore preserves record meaning and source bytes',
        );

        await _freshAuthority(folder, review, host);
        _check(
          (await store.purchaseStates()).isEmpty,
          'restoring backup grants no purchase',
        );
        await store.verifySimulatedOriginalPurchase();
        _check(
          (await store.access()).canCustomiseFields,
          'legacy Custom Fields grant survives',
        );
        await store.saveSetting('offline', 'false');
        final product = 'template:${pilot.id}';
        await store.startSimulatedPurchase(product);
        await _reject<TemplateAllowanceException>(() => add(restoredId));
        await store.acceptSimulatedPurchase(
          product,
          PurchaseState.verified,
          attempt: (await store.purchaseStates())['attempt:$product'],
        );
        for (final tile in [
          restoredId,
          second,
          third,
          extra,
          await place('Owned future tile', updated),
        ]) {
          await add(tile);
        }
        _check(
          (await store.evaluationStatus(pilot.id)).owned &&
              (await store.evaluationStatus(independent.id)).used == 1,
          'restored purchase unlocks all versions and placements of one template',
        );
      } finally {
        await review.dispose();
      }
    } finally {
      await archive.dispose();
    }

    await repository.saveHostValue(
      TemplateEvaluationLedger.namespace,
      'template:${independent.id}',
      'invalid',
    );
    _check(
      !(await store.evaluationStatus(independent.id)).canCreate,
      'malformed usage stays closed',
    );
    await _reject<TemplateAllowanceException>(() => add(other));
    await repository.removeHostValue(
      TemplateEvaluationLedger.namespace,
      'schema',
    );
    _check(
      (await store.evaluationStatus(pilot.id)).owned &&
          (await store.begin(ProfessionKind.standard)).kind ==
              ProfessionKind.standard,
      'missing authority leaves purchases and Standard recording available',
    );
  } finally {
    await repository.close();
  }
}

Future<void> _freshAuthority(
  Directory root,
  CollectionBackupReview review,
  ProfessionCreationStore Function(SqliteRecordingRepository) host,
) async {
  final workspace = RecordingWorkspace(
    await Directory(p.join(root.path, 'second-authority')).create(),
  );
  final originals = ManagedAttachmentFiles(
    workspace.originals,
    syncDirectory: syncOriginalDirectory,
  );
  final repository = await SqliteRecordingRepository.open(
    workspace.databasePath,
    durableWrites: true,
  );
  final backup = cpdCollectionBackup(_capacity, evaluationLedger: ledger);
  final store = host(repository);
  Future<CollectionImportResult> restore({
    Future<void> Function()? beforeCommit,
  }) => backup.restore(
    review: review,
    repository: repository,
    originals: originals,
    label: 'Other device history',
    beforeCommit: beforeCommit,
  );
  try {
    await ledger.initialise(repository);
    await _reject<StateError>(
      () => restore(
        beforeCommit: () async => throw StateError('synthetic interruption'),
      ),
    );
    _check(
      (await store.evaluationStatus(nursingPilot.id)).used == 0 &&
          (await repository.loadCollections()).isEmpty,
      'interrupted restore rolls back both history and usage',
    );
    final added = await restore();
    final id = added.collection!.id;
    _check(
      (await store.evaluationStatus(nursingPilot.id)).used == 2,
      'fresh authority counts each imported origin, including soft-deleted',
    );
    await repository.updateCollection(id, deleted: true);
    await backup.purgeDeletedCollection(repository, id);
    final restoredAgain = (await restore()).collection!.id;
    _check(
      (await store.evaluationStatus(nursingPilot.id)).used == 2,
      'repeat import counts original IDs once after purge',
    );
    final reexport = await backup.create(
      repository: repository,
      collectionId: restoredAgain,
      originals: originals.root,
      temporary: root,
    );
    try {
      final recheck = await backup.inspect(
        source: await reexport.fileForSharing(),
        temporary: root,
      );
      try {
        await repository.updateCollection(restoredAgain, deleted: true);
        await backup.purgeDeletedCollection(repository, restoredAgain);
        final result = await backup.restore(
          review: recheck,
          repository: repository,
          originals: originals,
          label: 'Re-exported history',
        );
        _check(
          result.status == CollectionImportStatus.added &&
              (await store.evaluationStatus(nursingPilot.id)).used == 2,
          're-export retains the original identities after remapping',
        );
      } finally {
        await recheck.dispose();
      }
    } finally {
      await reexport.dispose();
    }

    final portable = cpdPortableBackup(_capacity);
    final file = File(p.join(root.path, 'whole.recordingbackup'));
    final inspection = await portable.create(
      repository: repository,
      originals: originals.root,
      destination: file,
    );
    final candidate = await portable.restore(
      source: file,
      inspection: inspection,
      destination: Directory(p.join(root.path, 'portable-candidate')),
    );
    final imported = await SqliteRecordingRepository.open(
      candidate.databasePath,
    );
    try {
      _check(
        (await imported.loadHostState(
          TemplateEvaluationLedger.namespace,
        )).isEmpty,
        'whole-store portable backup cannot activate the allowance ledger',
      );
    } finally {
      await imported.close();
    }
  } finally {
    await repository.close();
  }
}

String _binding(LayoutRevision layout, String definition) =>
    layout.fields.singleWhere((field) => field.definition.id == definition).id;

Map<String, Object> _values(
  LayoutRevision layout,
  List<RecordingAttachment> evidence,
) => {
  _binding(layout, 'cpd.activityDate'): '2026-08-14',
  _binding(layout, 'cpd.title'): 'Synthetic activity',
  _binding(layout, 'cpd.details'): 'Evidence and allowance validation',
  _binding(layout, 'cpd.creditedDuration'): 45,
  _binding(layout, 'nmc.method'): 'online',
  _binding(layout, 'nmc.participatory'): 0,
  _binding(layout, 'nmc.code'): ['effective'],
  if (evidence.isNotEmpty)
    _binding(layout, 'cpd.evidence'): [for (final item in evidence) item.id],
};

TemplateVersion _recipe(String id, int version) => TemplateVersion(
  id: id,
  version: version,
  origin: nursingPilot.origin,
  label: nursingPilot.label,
  fields: nursingPilot.fields,
  headings: nursingPilot.headings,
);

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> _reject<T>(Future<void> Function() run) async {
  try {
    await run();
  } on Object catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}
