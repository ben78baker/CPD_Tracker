import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/recovery_retention.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:cpd_tracker/utils/csv_exporter.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart';
import 'package:cpd_tracker/utils/record_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'native_rehearsal_media.dart';

/// Use a disposable app with a distinct identifier, away from the tracker.
Future<void> main() async {
  final boot = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  final actions = ValueNotifier<RehearsalMedia?>(null);
  runApp(MaterialApp(home: RehearsalActions(samples: actions)));
  await WidgetsBinding.instance.endOfFrame;
  final frameMs = boot.elapsedMilliseconds;
  try {
    const mode = String.fromEnvironment(
      'CPD_PHASE3_MODE',
      defaultValue: 'scale',
    );
    if (mode == 'crash') {
      await _restartProbe();
      return;
    }
    actions.value = await RehearsalMedia.create(
      await getApplicationDocumentsDirectory(),
    );
    debugPrintSynchronously('CPD_PHASE3_UI_READY');
    final temp = await Directory.systemTemp.createTemp('cpd_phase3_');
    try {
      if (mode != 'actions') {
        for (final (records, photos) in [(32, 4), (420, 32), (3600, 96)]) {
          await _scale(temp, records, photos, frameMs, actions.value!.pdf);
        }
        await _reviewAndRetry(temp);
        await _history(temp);
        await _oversizedLegacyPayload(temp);
        debugPrintSynchronously('CPD_PHASE3_SCALE_PASS');
      }
      await rehearseLocalisedReports(temp);
    } finally {
      await temp.delete(recursive: true);
    }
  } catch (error, stack) {
    debugPrintSynchronously('CPD_PHASE3_FAIL $error\n$stack');
    rethrow;
  }
}

const _professions = [
  'Dentistry',
  'Education',
  'Engineering',
  'Nursing',
  'Pharmacy',
  'Surveying',
];

CpdEntry _entry(int index, String label, List<String> references) => CpdEntry(
  id: index + 1,
  profession: label,
  date: DateTime(2024, 1 + index % 12, 1 + index % 28),
  title: index % 13 == 0
      ? 'Case review and workshop'
      : 'Practice development $index',
  details:
      'Learning evidence and reflection. '
      '${'Follow-up and evaluation. ' * (3 + index % 14)}\nReviewed objectives.',
  hours: index % 3,
  minutes: index % 60,
  attachments: references,
  deleted: index % 61 == 0,
);

Map<String, Object?> _source(List<String> entries) => {
  'entries_json_list': entries,
  'professions': _professions,
  'deleted_professions': ['Surveying'],
  'next_entry_id': entries.length + 1,
  'targets_v1': jsonEncode({
    for (final label in _professions) label: {'minutes': 900, 'cycle': 'year'},
  }),
};

Future<void> _scale(
  Directory temp,
  int count,
  int photos,
  int frameMs,
  File pdf,
) async {
  final root = await temp.createTemp('scale_$count');
  final docs = await Directory(p.join(root.path, 'Documents')).create();
  final owned = await Directory(p.join(docs.path, 'attachments')).create();
  for (var i = 0; i < photos; i++) {
    await File(
      p.join(owned.path, 'study-$i.png'),
    ).writeAsBytes(rehearsalPhoto(640, i));
  }
  final pdfs = photos ~/ 2;
  for (var i = 0; i < pdfs; i++) {
    await pdf.copy(p.join(owned.path, 'certificate-$i.pdf'));
  }
  final entries = [
    for (var i = 0; i < count; i++)
      _entry(i, _professions[i % _professions.length], [
        if (i % 5 == 0) 'attachments/study-${(i ~/ 5) % photos}.png',
        if (i % 7 == 0) 'attachments/certificate-${(i ~/ 7) % pdfs}.pdf',
        if (i % 9 == 0) 'https://example.com/proof/$i',
        if (i % 111 == 0) 'attachments/missing-$i.pdf',
      ]).toJson(),
  ];
  final source = _source(entries);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('entries_json_list', entries);
  await prefs.setStringList('professions', _professions);
  await prefs.setStringList('deleted_professions', ['Surveying']);
  await prefs.setInt('next_entry_id', count + 1);
  await prefs.setString('targets_v1', source['targets_v1'] as String);
  final workspace = await Directory(p.join(root.path, 'attempt')).create();
  final decode = Stopwatch()..start();
  await prefs.reload();
  final legacy = await EntryRepository().loadAll();
  final baselineDecodeUs = decode.elapsedMicroseconds;
  final existingBytes =
      await _bytes(docs) + utf8.encode(encodeLegacySnapshot(source)).length;
  final baselineRss = ProcessInfo.currentRss;
  var peakRss = baselineRss;
  var peakWorkspace = 0;
  Future<void>? pendingSample;
  Future<void> sample() async {
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
    final bytes = await _bytes(workspace);
    if (bytes > peakWorkspace) peakWorkspace = bytes;
  }

  final timeline = <String, int>{};
  final watch = Stopwatch()..start();
  final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    pendingSample ??= sample().whenComplete(() => pendingSample = null);
  });
  final coordinator = CpdMigrationCoordinator(
    workspace: workspace,
    documents: docs,
    readLegacy: () => readCpdLegacyPreferences(prefs),
    onCheckpoint: (report) async {
      timeline[report.phase.name] = watch.elapsedMilliseconds;
      await sample();
    },
  );
  late MigrationReport report;
  try {
    report = await coordinator.rehearse();
  } finally {
    timer.cancel();
    await pendingSample;
    await sample();
  }
  final migrationMs = watch.elapsedMilliseconds;
  requireRehearsal(
    report.phase == MigrationPhase.ready,
    'Scale $count did not verify: ${report.encode()}',
  );
  requireRehearsal(
    await coordinator.readReceipt() == null,
    'Readiness leaves authority unset',
  );
  final reopen = Stopwatch()..start();
  final db = await SqliteRecordingRepository.open(coordinator.databasePath);
  try {
    final store = await SqliteCpdStore.openVerified(
      db,
      sourceId: report.sourceId!,
      documents: docs,
    );
    final openUs = reopen.elapsedMicroseconds;
    final search = Stopwatch()..start();
    final rows = await store.loadForProfession('Dentistry');
    final matches = RecordSearch.filter(rows, 'workshop');
    final searchUs = search.elapsedMicroseconds;
    final oldSearch = Stopwatch()..start();
    final oldMatches = RecordSearch.filter(
      legacy
          .where((row) => row.profession == 'Dentistry' && !row.deleted)
          .toList(),
      'workshop',
    );
    final oldSearchUs = oldSearch.elapsedMicroseconds;
    requireRehearsal(
      matches.length == oldMatches.length,
      'Search count matches legacy',
    );
    final range = DateTimeRange(
      start: DateTime(2024),
      end: DateTime(2024, 12, 31),
    );
    CpdExportSelection select(Iterable<CpdEntry> records) =>
        CpdExportSelection.fromVisibleRecords(
          profession: 'Dentistry',
          range: range,
          visibleRecords: records,
        );
    final csvWatch = Stopwatch()..start();
    final csv = buildCpdCsv(
      selection: select(rows),
      dateFormat: 'dd/MM/yyyy',
      texts: AppLocalizationsEn(),
    );
    final csvUs = csvWatch.elapsedMicroseconds;
    final pdfWatch = Stopwatch()..start();
    final reportPdf = await buildRecordsPdf(
      selection: select(rows.take(20)),
      dateFormat: 'dd/MM/yyyy',
      fonts: CpdPdfFonts.standard(),
      appIconBytes: rehearsalPhoto(16, 0),
      outputDirectory: root,
      attachmentPathResolver: (ref) async =>
          resolveStoredPathForDocumentsDirectory(ref, docs.path),
    );
    final pdfMs = pdfWatch.elapsedMilliseconds;
    debugPrintSynchronously(
      'CPD_PHASE3_SCALE ${jsonEncode({'records': count, 'professions': _professions.length, 'originals': photos + pdfs, 'legacyBytes': existingBytes, 'peakAdditionalBytes': peakWorkspace, 'peakRssBytes': peakRss, 'rssBeforeBytes': baselineRss, 'databaseBytes': await File(coordinator.databasePath).length(), 'migrationMs': migrationMs, 'checkpointsMs': timeline, 'scratchFirstFrameMs': frameMs, 'legacyDecodeUs': baselineDecodeUs, 'stagedOpenUs': openUs, 'legacySearchUs': oldSearchUs, 'projectedSearchUs': searchUs, 'matches': matches.length, 'csvUs': csvUs, 'csvBytes': utf8.encode(csv.text).length, 'pdf20Ms': pdfMs, 'pdfBytes': await reportPdf.length()})}',
    );
  } finally {
    await db.close();
  }
  await root.delete(recursive: true);
}

Future<void> _reviewAndRetry(Directory temp) async {
  final docs = await Directory(p.join(temp.path, 'review-docs')).create();
  final entry = _entry(1, 'Dentistry', [
    'content://unavailable/evidence',
  ]).toMap();
  final badDate = jsonEncode({...entry, 'date': '2024-02-30'});
  final fractional = jsonEncode({...entry, 'minutes': 12.25});
  final original = jsonEncode({
    ...entry,
    'legacyExtension': {'raw': true},
  });
  final source = _source([badDate, fractional, original, original]);
  final reviewing = CpdMigrationCoordinator(
    workspace: Directory(p.join(temp.path, 'review-attempt')),
    documents: docs,
    readLegacy: () async => source,
  );
  final result = await reviewing.rehearseActivation();
  final codes = result.review.map((item) => item.code).toSet();
  requireRehearsal(
    result.phase == MigrationPhase.reviewRequired &&
        codes.containsAll({
          'invalid_or_ambiguous_activity_date',
          'fractional_duration',
          'duplicate_legacy_id',
          'unsupported_evidence_reference',
          'unknown_record_fields_retained',
        }),
    'Manual review accounts for every malformed case',
  );
  requireRehearsal(
    await reviewing.readOriginalRow(0) == badDate &&
        await reviewing.readOriginalRow(1) == fractional &&
        await reviewing.readOriginalRow(3) == original,
    'Unresolved raw rows remain recoverable',
  );
  requireRehearsal(
    await reviewing.readReceipt() == null &&
        await reviewing.retention() == RecoveryRetention.keepUntilActivation,
    'Review prevents activation and pins the recovery copy',
  );

  final good = _source([_entry(1, 'Dentistry', []).toJson()]);
  var low = true;
  var probes = 0;
  var clock = DateTime.now().toUtc().add(const Duration(minutes: 1));
  final coordinator = CpdMigrationCoordinator(
    workspace: Directory(p.join(temp.path, 'retry-attempt')),
    documents: docs,
    readLegacy: () async => good,
    availableStorage: (directory) async =>
        low && ++probes == 3 ? 1024 : availableDeviceStorage(directory),
    clock: () => clock,
  );
  final blocked = await coordinator.rehearseActivation();
  requireRehearsal(
    blocked.failure == 'insufficient_storage' &&
        await coordinator.snapshot.directory.exists() &&
        !await File(coordinator.databasePath).exists(),
    'Capacity falls after recovery and before SQLite',
  );
  low = false;
  final ready = await coordinator.rehearse();
  requireRehearsal(
    ready.phase == MigrationPhase.ready &&
        await coordinator.readReceipt() == null,
    'Retry retains the independent recovery copy',
  );
  final result2 = await coordinator.rehearseActivation();
  final receipt = await coordinator.readReceipt();
  requireRehearsal(
    result2.phase == MigrationPhase.rehearsalActivated &&
        receipt?.rehearsal == true,
    'Only rehearsal authority can be recorded',
  );
  requireRehearsal(
    await coordinator.retention(activeStoreIntegrityConfirmed: true) ==
        RecoveryRetention.keepForMinimumPeriod,
    'Retention starts at activation',
  );
  clock = receipt!.retainUntil;
  requireRehearsal(
    await coordinator.retention(activeStoreIntegrityConfirmed: true) ==
            RecoveryRetention.eligibleForManualReview &&
        await coordinator.snapshot.directory.exists(),
    'Reaching 30 days never deletes a recovery copy',
  );
  requireRehearsal(
    (await coordinator.activateProduction()).phase == MigrationPhase.disabled,
    'Production activation is disabled',
  );
  debugPrintSynchronously('CPD_PHASE3_REVIEW_RETRY_PASS');
}

Future<void> _history(Directory temp) async {
  final repo = await SqliteRecordingRepository.open(
    p.join(temp.path, 'history.sqlite'),
  );
  try {
    final collection = await repo.createCollection('Equipment');
    for (final (version, label) in [(1, 'Certified'), (2, 'Approved')]) {
      final template = TemplateVersion(
        id: 'inspection',
        version: version,
        label: 'Inspection',
        fields: [
          LayoutField(
            id: 'status',
            definition: FieldDefinition(
              id: 'status',
              version: version,
              label: 'Status',
              kind: FieldKind.choice,
              choices: {'valid': label},
            ),
          ),
        ],
      );
      await repo.saveTemplate(template);
      final layout = await repo.applyTemplate(
        collection.id,
        template,
        expectedVersion: version,
      );
      await repo.createRecord(collection.id, {
        layout.fields.single.id: 'valid',
      }, expectedLayoutVersion: version + 1);
    }
    final revisions = await repo.loadLayouts(collection.id);
    final all = await repo.loadAllRecords();
    requireRehearsal(
      all[0].project(resolveFields(all[0].layoutVersion, revisions)).single ==
              'Certified' &&
          all[1]
                  .project(resolveFields(all[1].layoutVersion, revisions))
                  .single ==
              'Approved',
      'Historical template versions survive the batch read',
    );
  } finally {
    await repo.close();
  }
  debugPrintSynchronously('CPD_PHASE3_HISTORY_PASS');
}

Future<void> _oversizedLegacyPayload(Directory root) async {
  final path = p.join(root.path, 'inline-v2.sqlite');
  final setup = await SqliteRecordingRepository.open(path);
  await setup.close();
  final legacy = await databaseFactory.openDatabase(path);
  final data = jsonEncode({'payload': 'é🚀' * 400000});
  await legacy.execute('DROP TABLE import_payload_chunks');
  await legacy.execute('PRAGMA user_version = 2');
  await legacy.insert('import_snapshots', {
    'source_id': 'old',
    'status': 'captured',
    'raw': data,
    'metadata': data,
  });
  await legacy.close();
  final repository = await SqliteRecordingRepository.open(path);
  try {
    final recovered = await repository.loadImportSnapshot('old');
    requireRehearsal(
      recovered?.raw == data && recovered?.metadata == data,
      'Recover existing v2 inline payload larger than Android CursorWindow',
    );
    await repository.captureImport('new', data);
    final chunked = await repository.loadImportSnapshot('new');
    requireRehearsal(
      chunked?.raw == data,
      'UTF-8 chunks retain non-ASCII text',
    );
  } finally {
    await repository.close();
  }
  debugPrintSynchronously('CPD_PHASE3_BOUNDED_PAYLOAD_PASS');
}

Future<void> _restartProbe() async {
  const point = String.fromEnvironment(
    'CPD_PHASE3_EXIT_AT',
    defaultValue: 'verifying',
  );
  final checkpoint = MigrationPhase.values.byName(point);
  final support = await getApplicationSupportDirectory();
  final root = await Directory(
    p.join(support.path, 'cpd_phase3_restart_$point'),
  ).create();
  final docs = await Directory(p.join(root.path, 'Documents')).create();
  final source = _source([_entry(1, 'Dentistry', []).toJson()]);
  var pause = false;
  final coordinator = CpdMigrationCoordinator(
    workspace: Directory(p.join(root.path, 'attempt')),
    documents: docs,
    readLegacy: () async => source,
    onCheckpoint: (report) async {
      if (pause && report.phase == checkpoint) {
        debugPrintSynchronously('CPD_PHASE3_KILL_READY');
        await Future<void>.delayed(const Duration(minutes: 7));
        throw StateError('The disposable launcher did not terminate the app.');
      }
    },
  );
  final before = await coordinator.lastReport();
  if (before == null) {
    pause = true;
    await coordinator.rehearseActivation();
    throw StateError(
      'The first process should be terminated at the checkpoint.',
    );
  }
  requireRehearsal(
    before.phase == checkpoint && await coordinator.readReceipt() == null,
    'Interrupted staging has no authority',
  );
  await coordinator.snapshot.verify();
  if (checkpoint == MigrationPhase.handoffReserved) {
    final authority = await coordinator.startup.inspect(
      scope: AuthorityScope.rehearsal,
      hasLegacyRecords: true,
    );
    requireRehearsal(
      authority.store == StoreAuthority.recovery &&
          authority.reason == AuthorityReason.interruptedHandoff &&
          (await coordinator.rehearseActivation()).failure ==
              'handoff_requires_recovery',
      'A stopped handoff must not reopen or rebuild legacy.',
    );
    debugPrintSynchronously('CPD_PHASE3B_HANDOFF_RESTART_PASS');
    return;
  }
  final restarted = await coordinator.rehearseActivation();
  requireRehearsal(
    restarted.phase == MigrationPhase.rehearsalActivated,
    'Restart completes verified rehearsal',
  );
  final receipt = await coordinator.readReceipt();
  await coordinator.rehearseActivation();
  requireRehearsal(
    (await coordinator.readReceipt())?.encode() == receipt?.encode(),
    'Retry keeps the original activation time',
  );
  debugPrintSynchronously('CPD_PHASE3_RESTART_PASS');
}

Future<int> _bytes(Directory directory) async {
  var total = 0;
  await for (final item in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (item is! File) continue;
    try {
      total += await item.length();
    } on FileSystemException {
      // SQLite can remove its journal between listing and stat.
    }
  }
  return total;
}
