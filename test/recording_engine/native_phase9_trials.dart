import 'dart:io';

import 'package:cpd_tracker/cpd_backup/cpd_collection_backup.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/sqlite_template_trial_ledger.dart';
import 'package:cpd_tracker/cpd_creation/template_trials.dart';
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

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(home: Scaffold(body: Text('Phase 9 synthetic trials'))),
  );
  final folder = await Directory.systemTemp.createTemp('phase9_trials_');
  try {
    await _verify(folder);
    debugPrintSynchronously('CPD_PHASE9_NATIVE_PASS');
  } on Object catch (error, stack) {
    debugPrintSynchronously('CPD_PHASE9_NATIVE_FAIL $error\n$stack');
    rethrow;
  } finally {
    await folder.delete(recursive: true);
  }
}

Future<void> _verify(Directory folder) async {
  final workspace = RecordingWorkspace(folder);
  final originals = ManagedAttachmentFiles(
    workspace.originals,
    syncDirectory: syncOriginalDirectory,
  );
  final backup = cpdCollectionBackup((_) async => 64 * 1024 * 1024);
  final ledgerFile = File(p.join(folder.path, 'trials.sqlite'));
  var ledger = SqliteTemplateTrialLedger(ledgerFile);
  await ledger.provision();
  var repository = await SqliteRecordingRepository.open(
    workspace.databasePath,
    durableWrites: true,
  );
  final original = DateTime.utc(2026, 11, 21, 12);
  var now = original;
  var elapsed = Duration.zero;
  final pilot = nursingPilot;
  final updated = _recipe(pilot.id, 2);
  final independent = _recipe('fixture-independent', 1);
  ProfessionCreationStore host() => ProfessionCreationStore(
    repository,
    templates: {
      (pilot.id, 1): pilot,
      (updated.id, 2): updated,
      (independent.id, 1): independent,
    },
    reportRules: {
      (pilot.id, 1): nursingReportRules,
      (updated.id, 2): nursingReportRules,
    },
    bundles: {(pilot.id, 1): nursingBundle},
    trialLedger: ledger,
    trialClock: TrialClock(utcNow: () => now, elapsed: () => elapsed),
  );
  var store = host();
  Future<String> place(String name, TemplateVersion recipe) async {
    final draft = (await store.begin(
      ProfessionKind.template,
      recipe: recipe,
    )).withChanges(name: name);
    await store.persist(draft);
    return store.commit(draft.id);
  }

  try {
    await store.saveSetting('offline', 'true');
    final start = await Future.wait([
      store.startTrial(pilot.id),
      store.startTrial(pilot.id),
    ]);
    _check(
      start.every(
        (status) =>
            status.started == original &&
            status.expires == original.add(templateTrialDuration),
      ),
      'offline duplicate activation has one UTC interval',
    );
    _check(!(await store.access()).canCustomiseFields, 'no wider grant');
    _check(
      (await store.purchaseStates()).isEmpty,
      'a trial creates no purchase',
    );
    await store.verifySimulatedOriginalPurchase();
    _check(
      (await store.access()).canCustomiseFields,
      'legacy grant remains available',
    );
    final first = await place('Nurse trial', pilot);
    final second = await place('Nurse trial second tile', pilot);
    _check(first != second, 'separate placements');
    final v2 = await place('Nurse trial newer version', updated);
    _check(
      (await repository.loadLayouts(v2)).last.templateVersion == 2,
      'same id can use another recipe version',
    );
    _check(
      (await store.startTrial(updated.id)).started == original,
      'template update cannot start another trial',
    );
    await repository.updateCollection(second, deleted: true);
    await repository.updateCollection(second, deleted: false);
    _check(
      (await store.trialStatus(pilot.id)).started == original,
      'delete and restore have no effect on expiry',
    );
    now = original.add(const Duration(days: 1));
    elapsed += const Duration(days: 1);
    final other = await store.startTrial(independent.id);
    _check(
      other.started == now && other.expires != start.first.expires,
      'independent identity gets its own window',
    );

    var history = await repository.loadLayouts(first);
    var active = history.last;
    final fields = {
      for (final field in active.fields) field.definition.id: field.id,
    };
    final photo = File(p.join(folder.path, 'fixture.png'));
    await photo.writeAsBytes(
      image.encodePng(image.Image(width: 12, height: 12)),
    );
    final pdf = File(p.join(folder.path, 'fixture.pdf'));
    final sample = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Synthetic certificate')));
    await pdf.writeAsBytes(await sample.save());
    final evidence = [
      await originals.copyOriginal(photo),
      await originals.copyOriginal(pdf),
    ];
    final values = <String, Object>{
      fields['cpd.activityDate']!: '2026-08-14',
      fields['cpd.title']!: 'Synthetic trial record',
      fields['cpd.details']!: 'Evidence preservation',
      fields['cpd.creditedDuration']!: 45,
      fields['nmc.method']!: 'online',
      fields['nmc.participatory']!: 0,
      fields['nmc.code']!: ['effective'],
      fields['cpd.evidence']!: [for (final one in evidence) one.id],
    };
    final record = await store.createActivity(
      first,
      values,
      expectedLayoutVersion: active.version,
      newAttachments: evidence,
    );
    final edited = await store.updateActivity(record.id, {
      fields['nmc.method']!: 'workshop',
    }, expectedVersion: record.version);
    _check(
      edited.values[fields['nmc.method']] == 'workshop',
      'controlled values can be edited in trial',
    );
    await store.requireOwnedReport(active);
    await SchemePeriodStore(repository).select(
      first,
      rehearsalPeriod,
      canChange: (tx) => store.checkTrialTemplateAccess(tx, pilot.id),
    );
    final draft = await store.beginEdit(first);
    final archive = await backup.create(
      repository: repository,
      collectionId: first,
      originals: originals.root,
      temporary: folder,
    );
    final file = await archive.fileForSharing();
    final checksum = await backupDigest(file);

    await ledger.close();
    await repository.close();
    ledger = SqliteTemplateTrialLedger(ledgerFile);
    repository = await SqliteRecordingRepository.open(
      workspace.databasePath,
      durableWrites: true,
    );
    store = host();
    _check(
      (await store.trialStatus(pilot.id)).started == original,
      'account trial history survives app restart',
    );
    now = original.add(templateTrialDuration);
    await _reject<TemplateAccessException>(
      () => store.createActivity(
        first,
        values,
        expectedLayoutVersion: active.version,
      ),
    );
    await _reject<TemplateAccessException>(
      () => store.updateActivity(record.id, {
        fields['nmc.method']!: 'other',
      }, expectedVersion: edited.version),
    );
    await _reject<TemplateAccessException>(() => store.commit(draft.id));
    _check(
      (await repository.loadRecord(record.id))!.version == edited.version,
      'expired save preserves historical edits',
    );
    _check(
      (await store.trialStatus(independent.id)).active,
      'another trial is still active',
    );

    await store.requireHistoricalReport(active);
    final historical = await loadSchemeProgress(
      repository: repository,
      bundle: nursingBundle,
      period: rehearsalPeriod,
      history: history,
      records: [edited],
      originals: originals,
    );
    _check(
      historical.evidence.values.where((asset) => asset.available).length == 2,
      'both originals available after expiry',
    );
    final report = await buildSchemeReport(
      bundle: nursingBundle,
      progress: historical.progress,
      bindings: historical.bindings,
      evidence: historical.evidence,
      strings: AppLocalizationsEn(),
      practitioner: 'Sample',
    );
    _check(
      String.fromCharCodes(report.take(5)) == '%PDF-',
      'historical scheme PDF',
    );
    final rows = recordExportRows(
      edited,
      resolveFields(edited.layoutVersion, history),
    );
    _check(
      rows.any((row) => row.last.contains('Workshop')),
      'historical CSV projection retains choice meaning',
    );

    // A verified archive goes back into this authority after deleting the tile.
    await repository.updateCollection(first, deleted: true);
    await backup.purgeDeletedCollection(repository, first);
    final inspected = await backup.inspect(source: file, temporary: folder);
    final imported = await backup.restore(
      review: inspected,
      repository: repository,
      originals: originals,
      label: 'Restored trial',
    );
    await inspected.dispose();
    _check(
      imported.status == CollectionImportStatus.added,
      'archive can be restored without owning the template',
    );
    final restoreId = imported.collection!.id;
    history = await repository.loadLayouts(restoreId);
    active = history.last;
    final restored = (await repository.loadRecords(restoreId)).single;
    final restoredRefs = (restored.values[fields['cpd.evidence']] as List)
        .cast<String>();
    final restoredDigests = <String>{};
    for (final ref in restoredRefs) {
      final item = (await repository.loadAttachment(ref))!;
      restoredDigests.add(
        await backupDigest((await originals.resolveOriginal(item))!),
      );
    }
    _check(
      restoredDigests.containsAll(
        evidence.map((item) => item.originalFingerprint),
      ),
      'photo and PDF bytes survive restored trial',
    );
    _check(
      (await store.trialStatus(pilot.id)).state == TemplateTrialState.ended &&
          !(await store.canAddToLayout(active)),
      'restore cannot renew access',
    );
    _check(
      (await store.purchaseStates()).keys.single == 'legacy',
      'archive adds no purchase or app-wide grant',
    );
    _check(
      restored.values[fields['nmc.method']] == 'workshop' &&
          await backupDigest(file) == checksum,
      'restored record and source preserve values',
    );
    await archive.dispose();

    await store.acceptSimulatedPurchase(
      'template:${pilot.id}',
      PurchaseState.verified,
    );
    _check(
      (await store.startTrial(pilot.id)).state == TemplateTrialState.owned &&
          await store.canAddToLayout(active),
      'verified restore overrides expired trial',
    );
    await store.acceptSimulatedPurchase(
      'template:${independent.id}',
      PurchaseState.verified,
    );
    _check(
      (await store.trialStatus(independent.id)).state ==
          TemplateTrialState.owned,
      'purchase during a trial gives permanent access',
    );

    await ledger.close();
    await ledgerFile.delete();
    _check(
      (await store.startTrial(updated.id)).state == TemplateTrialState.owned,
      'missing trial history cannot block paid users',
    );
    final unowned = _recipe('fixture-new-unowned', 1);
    final missing = ProfessionCreationStore(
      repository,
      templates: {(unowned.id, 1): unowned},
      reportRules: {},
      trialLedger: ledger,
    );
    _check(
      (await missing.startTrial(unowned.id)).state ==
              TemplateTrialState.unavailable &&
          !await ledgerFile.exists(),
      'missing history is not reissued',
    );
    await ledgerFile.writeAsString('not a SQLite database');
    _check(
      (await missing.startTrial(unowned.id)).state ==
          TemplateTrialState.unavailable,
      'malformed authority grants nothing',
    );
    _check(
      (await missing.begin(ProfessionKind.standard)).kind ==
          ProfessionKind.standard,
      'free route survives ledger failure',
    );
  } finally {
    await ledger.close();
    await repository.close();
  }
}

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
