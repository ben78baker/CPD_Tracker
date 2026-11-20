import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/legacy_recovery_snapshot.dart';
import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/import_plan.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:cpd_tracker/utils/csv_exporter.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart';
import 'package:cpd_tracker/utils/record_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Run only in a disposable mobile application with a distinct application ID.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('CPD compatibility validation')),
    ),
  );
  try {
    if (const bool.fromEnvironment('CPD_PARITY_EXIT')) {
      await _processExit();
      return;
    }
    final scratch = await Directory.systemTemp.createTemp('cpd_parity_');
    try {
      await _entryProfessionAndExportParity(scratch);
      await _ambiguousAndDuplicate(scratch);
      await _separateRecovery(scratch);
      await _databaseFull(scratch);
      await _upgrade(scratch);
      debugPrintSynchronously('CPD_PARITY_PASS: 5 scenarios');
    } finally {
      await scratch.delete(recursive: true);
    }
  } catch (error, stack) {
    debugPrintSynchronously('CPD_PARITY_FAIL: $error\n$stack');
    rethrow;
  }
}

Future<void> _entryProfessionAndExportParity(Directory scratch) async {
  final documents = await Directory(p.join(scratch.path, 'Documents')).create();
  final originalPhoto = await _write(documents, 'photo.png', _photo());
  final originalPdf = await _write(documents, 'course.pdf', await _sourcePdf());
  final originalFile = await _write(
    documents,
    'reflection.docx',
    utf8.encode('Synthetic unsupported original'),
  );
  const url = 'https://example.com/cpd';
  const email = 'mailto:training@example.com';
  const tel = 'tel:+442000000000';
  const missing = 'attachments/missing.png';
  final first = _entry(
    3,
    ' Dentistry ',
    day: DateTime(2024, 2, 29),
    title: 'Course, "Audit"',
    details: 'Line one\nLine two',
    attachments: [
      'attachments/photo.png',
      '/old/container/Documents/attachments/course.pdf',
      url,
      email,
      tel,
      missing,
    ],
  );
  final second = _entry(
    1,
    'Dentistry',
    day: DateTime(2024, 3, 1),
    title: 'Supporting document',
    attachments: ['attachments/reflection.docx'],
  );
  final deleted = _entry(2, 'Nurse', deleted: true);
  final orphan = _entry(4, 'Orphan', deleted: true);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('professions', ['Dentistry', 'Nurse']);
  await prefs.setStringList('deleted_professions', ['Nurse']);
  await prefs.setStringList(
    'entries_json_list',
    [first, second, deleted, orphan].map((row) => row.toJson()).toList(),
  );
  await prefs.setInt('next_entry_id', 5);
  await prefs.setString(
    'targets_v1',
    '{"Dentistry":{"minutes":120,"cycle":"month"},'
        '"nurse":{"minutes":600,"cycle":"year","legacyExtension":true}}',
  );
  await prefs.setString('date_format', 'yyyy-MM-dd');
  await prefs.setString('week_start', 'saturday');
  await prefs.setString('profile_company', 'Synthetic CPD organisation');
  final source = await readCpdLegacyPreferences(prefs);
  final dbPath = p.join(scratch.path, 'parity.sqlite');
  var db = await SqliteRecordingRepository.open(dbPath);
  final legacy = EntryRepository();
  final settings = SettingsStore.instance;
  try {
    final migration = SyntheticCpdMigration(db, documents);
    _same(await migration.stage(source), ImportStatus.staged, 'initial stage');
    await _rejects<StateError>(
      () => SqliteCpdStore.openVerified(
        db,
        sourceId: SyntheticCpdMigration.sourceIdentity(source),
        documents: documents,
      ),
    );
    await migration.verify(source);
    final sourceId = SyntheticCpdMigration.sourceIdentity(source);
    final next = await SqliteCpdStore.openVerified(
      db,
      sourceId: sourceId,
      documents: documents,
    );
    Future<void> compareEntries() async => _same(
      (await legacy.loadAll()).map((entry) => entry.toMap()).toList(),
      (await next.loadAll()).map((entry) => entry.toMap()).toList(),
      'record values and ordering',
    );
    await compareEntries();
    _same(
      await readCpdLegacyPreferences(prefs),
      source,
      'SQLite preparation leaves preferences untouched',
    );
    _same(
      await next.getTarget('Nurse'),
      await settings.getTarget('Nurse'),
      'legacy target exact-case lookup',
    );
    _same(
      await next.getTarget('nurse'),
      await settings.getTarget('nurse'),
      'legacy target alias lookup',
    );
    _same(
      await next.loadActiveProfessions(),
      await settings.loadActiveProfessions(),
      'visible professions',
    );
    final matching = await legacy.loadForProfession(' Dentistry ');
    final projected = await next.loadForProfession(' Dentistry ');
    _same(
      RecordSearch.filter(
        projected,
        ' CoUrSe.PdF ',
      ).map((row) => row.id).toList(),
      RecordSearch.filter(
        matching,
        ' CoUrSe.PdF ',
      ).map((row) => row.id).toList(),
      'attachment search',
    );
    _same(
      RecordSearch.groupByProfession(projected, 'line two').keys.toList(),
      RecordSearch.groupByProfession(matching, 'line two').keys.toList(),
      'raw label used by global search',
    );
    for (final cycle in ['week', 'month', 'year']) {
      final (start, end) = cpdTargetPeriod(
        DateTime(2024, 2, 29),
        cycle,
        firstWeekday: DateTime.saturday,
      );
      final total = await next.sumMinutesForRange('Dentistry', start, end);
      _same(
        total,
        await settings.sumMinutesForRange('Dentistry', start, end),
        '$cycle CPD total',
      );
      _same(total, cycle == 'month' ? 65 : 130, '$cycle boundary expectation');
    }
    await _exports(
      scratch,
      documents,
      matching,
      projected,
      originalPhoto: originalPhoto,
      originalPdf: originalPdf,
      originalFile: originalFile,
    );

    final createdLegacy = await legacy.createAndSave(
      profession: 'Dentistry',
      date: DateTime(2024, 2, 28),
      title: 'Reflection',
      details: 'Ligne 1\n学習',
      hours: 0,
      minutes: 25,
      attachments: [url, missing],
    );
    final createdNext = await next.createAndSave(
      profession: 'Dentistry',
      date: DateTime(2024, 2, 28),
      title: 'Reflection',
      details: 'Ligne 1\n学習',
      hours: 0,
      minutes: 25,
      attachments: [url, missing],
    );
    _same(
      createdLegacy.toMap(),
      createdNext.toMap(),
      'create with duration and attachments',
    );
    final edited = _entry(
      3,
      ' Dentistry ',
      day: DateTime(2024, 2, 28),
      title: 'Refreshed course',
      details: 'Long note\n第二行',
      attachments: [
        missing,
        url,
        'attachments/photo.png',
        'attachments/photo.png',
      ],
    );
    await legacy.updateEntry(edited);
    await next.updateEntry(edited);
    await compareEntries();
    await legacy.setDeleted(1, true);
    await next.setDeleted(1, true);
    _same(
      (await next.loadDeleted()).map((row) => row.id).toList(),
      (await legacy.loadDeleted()).map((row) => row.id).toList(),
      'deleted record order',
    );
    await _rejects<StateError>(() => settings.restoreRecord(2));
    await _rejects<StateError>(() => next.restoreRecord(2));
    await settings.restoreRecord(2, recoverProfession: true);
    await next.restoreRecord(2, recoverProfession: true);
    await _rejects<StateError>(() => settings.restoreRecord(4));
    await _rejects<StateError>(() => next.restoreRecord(4));
    await settings.restoreRecord(4, recoverProfession: true);
    await next.restoreRecord(4, recoverProfession: true);
    await settings.addProfession(' engineer ');
    await next.addProfession(' engineer ');
    await _rejects<StateError>(
      () => settings.renameProfession('Dentistry', 'Nurse'),
    );
    await _rejects<StateError>(
      () => next.renameProfession('Dentistry', 'Nurse'),
    );
    await settings.renameProfession('Dentistry', 'Dental care');
    await next.renameProfession('Dentistry', 'Dental care');
    _same(
      await next.getTarget('Dental care'),
      await settings.getTarget('Dental care'),
      'target follows rename',
    );
    await settings.setTarget('Engineer', minutes: 125, cycle: 'week');
    await next.setTarget('Engineer', minutes: 125, cycle: 'week');
    _same(
      await next.getTarget('Engineer'),
      await settings.getTarget('Engineer'),
      'target update',
    );
    await settings.clearTarget('Engineer');
    await next.clearTarget('Engineer');
    _same(
      await next.getTarget('Engineer'),
      await settings.getTarget('Engineer'),
      'target removal',
    );
    await settings.softDeleteProfession('Dental care');
    await next.softDeleteProfession('Dental care');
    _same(
      await next.loadActiveProfessions(),
      await settings.loadActiveProfessions(),
      'soft delete visibility',
    );
    _same(
      await next.loadDeletedProfessions(),
      await settings.loadDeletedProfessions(),
      'archived names',
    );
    await settings.restoreProfession('Dental care');
    await next.restoreProfession('Dental care');
    await compareEntries();
    await db.close();
    db = await SqliteRecordingRepository.open(dbPath);
    final reopened = await SqliteCpdStore.openVerified(
      db,
      sourceId: sourceId,
      documents: documents,
    );
    _same(
      (await reopened.loadAll()).map((entry) => entry.toMap()).toList(),
      (await legacy.loadAll()).map((entry) => entry.toMap()).toList(),
      'reopen preserves all changes',
    );
    _same(
      await reopened.loadActiveProfessions(),
      await settings.loadActiveProfessions(),
      'reopened active names',
    );
    _same(
      await originalPhoto.readAsBytes(),
      _photo(),
      'attachment edits retain original photograph',
    );
    _same(
      (await settings.loadProfile())['company'],
      'Synthetic CPD organisation',
      'profile remains in settings',
    );
    _same(await settings.getWeekStart(), 'saturday', 'week settings preserved');
    _same(
      await settings.getDateFormat(),
      'yyyy-MM-dd',
      'date settings preserved',
    );
    debugPrintSynchronously(
      'CPD_PARITY_OK: entries, professions, settings, targets, search and actual exports',
    );
  } finally {
    await db.close();
  }
}

Future<void> _exports(
  Directory scratch,
  Directory documents,
  List<CpdEntry> baseline,
  List<CpdEntry> compatible, {
  required File originalPhoto,
  required File originalPdf,
  required File originalFile,
}) async {
  _check(
    (await Printing.info()).canRaster,
    'native PDF rasterisation must be available',
  );
  CpdExportSelection select(
    List<CpdEntry> rows, {
    required bool includeUnsupported,
  }) => CpdExportSelection.fromVisibleRecords(
    profession: 'Dentistry',
    range: DateTimeRange(
      start: DateTime(2024, 2, 29),
      end: DateTime(
        2024,
        includeUnsupported ? 3 : 2,
        includeUnsupported ? 1 : 29,
      ),
    ),
    visibleRecords: RecordSearch.filter(rows, ''),
  );
  Future<String> resolve(String stored) async =>
      resolveStoredPathForDocumentsDirectory(stored, documents.path);
  for (final includeUnsupported in [false, true]) {
    final left = select(baseline, includeUnsupported: includeUnsupported);
    final right = select(compatible, includeUnsupported: includeUnsupported);
    String csv(CpdExportSelection selection) => buildCpdCsv(
      selection: selection,
      dateFormat: 'yyyy-MM-dd',
      texts: AppLocalizationsEn(),
      userName: 'Synthetic User',
    ).text;
    _same(csv(right), csv(left), 'CSV bytes');
    final signatures = <Object>[];
    for (final selection in [left, right]) {
      final dir = await scratch.createTemp('export_');
      late CpdPdfPresentation plain;
      late CpdPdfPresentation rich;
      final icon = _photo();
      final fonts = CpdPdfFonts.standard();
      final textPdf = await buildRecordsPdf(
        selection: selection,
        dateFormat: 'yyyy-MM-dd',
        userName: 'Synthetic User',
        attachmentPathResolver: resolve,
        fonts: fonts,
        appIconBytes: icon,
        outputDirectory: dir,
        onPresentationPrepared: (value) => plain = value,
      );
      final textStructure = await _pdfStructure(textPdf);
      final richPdf = await buildRecordsPdf(
        selection: selection,
        dateFormat: 'yyyy-MM-dd',
        userName: 'Synthetic User',
        attachmentPathResolver: resolve,
        fonts: fonts,
        appIconBytes: icon,
        outputDirectory: dir,
        evidenceMode: CpdPdfEvidenceMode.embeddedImages,
        onPresentationPrepared: (value) => rich = value,
      );
      final bundled = await buildRecordsPdfWithEvidenceArtifacts(
        selection: selection,
        dateFormat: 'yyyy-MM-dd',
        userName: 'Synthetic User',
        attachmentPathResolver: resolve,
        fonts: fonts,
        appIconBytes: icon,
        outputDirectory: dir,
      );
      _same(
        (plain.embeddedImageCount, plain.documentaryPageCount).toString(),
        '(0, 0)',
        'text-only PDF',
      );
      _same(
        (rich.embeddedImageCount, rich.documentaryPageCount).toString(),
        '(1, 2)',
        'photo and two source PDF pages',
      );
      _check(
        rich.records.first.evidence.any(
          (evidence) =>
              evidence.isUnavailable && evidence.label.contains('missing.png'),
        ),
        'missing attachment indicator',
      );
      _same(rich.hyperlinks.length, 3, 'https, mailto and telephone links');
      final richStructure = await _pdfStructure(richPdf);
      _same(richStructure['links'], 3, 'rendered clickable link annotations');
      _check(
        (richStructure['images']! as int) > 3,
        'rendered image objects include evidence',
      );
      _same(
        bundled.includesOriginalEvidenceZip,
        includeUnsupported,
        'conditional ZIP',
      );
      final zipped = <String, Object>{};
      if (bundled.originalEvidenceZip case final zip?) {
        final entries = ZipDecoder().decodeBytes(await zip.readAsBytes()).files;
        for (final proof in [originalPhoto, originalPdf, originalFile]) {
          final name = p.basename(proof.path);
          final item = entries.singleWhere(
            (item) => item.name.endsWith('/$name'),
          );
          _same(
            item.readBytes(),
            await proof.readAsBytes(),
            'original ZIP bytes',
          );
        }
        for (final entry in entries) {
          final isReport =
              entry.name.endsWith('.pdf') && !entry.name.contains('/');
          zipped[isReport ? 'report.pdf' : entry.name] = isReport
              ? await _pdfSignature(entry.readBytes()!)
              : base64Encode(entry.readBytes()!);
        }
        _check(
          zipped.keys.any((name) => name.endsWith('.txt')),
          'ZIP contains URL manifest',
        );
      }
      signatures.add([
        _pdfPresentation(plain),
        _pdfPresentation(rich),
        textStructure,
        richStructure,
        zipped,
      ]);
    }
    _same(signatures.first, signatures.last, 'semantic PDF and ZIP parity');
  }
}

Object _pdfPresentation(CpdPdfPresentation value) => [
  value.profile.name,
  value.profession,
  value.period,
  value.totalDuration,
  for (final row in value.records)
    [
      row.sourceId,
      row.date,
      row.title,
      row.details,
      row.duration,
      for (final evidence in row.evidence)
        [
          evidence.kind.name,
          evidence.category,
          evidence.label,
          evidence.destination?.toString(),
          evidence.isUnavailable,
          evidence.requiresOriginalBundle,
          if (evidence.image case final image?)
            [image.pixelWidth, image.pixelHeight, base64Encode(image.bytes)],
          for (final page in evidence.documentPages)
            [
              page.sourcePageNumber,
              page.totalSourcePages,
              page.pixelWidth,
              page.pixelHeight,
              base64Encode(page.bytes),
            ],
        ],
    ],
];

Future<Map<String, Object>> _pdfStructure(File file) async {
  return _pdfSignature(await file.readAsBytes());
}

Future<Map<String, Object>> _pdfSignature(Uint8List bytes) async {
  final pdf = latin1.decode(bytes);
  _check(pdf.startsWith('%PDF-'), 'PDF file header');
  int matches(String pattern) => RegExp(pattern).allMatches(pdf).length;
  final rendered = <List<int>>[];
  await for (final page in Printing.raster(bytes, dpi: 48)) {
    rendered.add([page.width, page.height, getCrc32(page.pixels)]);
  }
  _check(rendered.isNotEmpty, 'PDF contains rendered pages');
  return {
    'pixels': rendered,
    'pages': matches(r'/Type\s*/Page\b'),
    'links': matches(r'/URI\s*\('),
    'images': matches(r'/Subtype\s*/Image\b'),
  };
}

Future<void> _ambiguousAndDuplicate(Directory scratch) async {
  final fixtures = await Directory(p.join(scratch.path, 'malformed')).create();
  final raw = _entry(
    7,
    'Dentistry',
    details: 'Original text\n学習',
    attachments: [
      'attachments/missing.pdf',
      'content://provider/no-longer-available',
    ],
  ).toMap();
  final unknown = jsonEncode({
    ...raw,
    'extension': {'exact': 'opaque'},
  });
  final source = <String, Object?>{
    'professions': ['Dentistry'],
    'entries_json_list': [unknown, unknown],
    'next_entry_id': 1,
  };
  final db = await SqliteRecordingRepository.open(
    p.join(fixtures.path, 'duplicates.sqlite'),
  );
  try {
    final migrate = SyntheticCpdMigration(db, fixtures);
    _same(
      await migrate.stage(source),
      ImportStatus.staged,
      'duplicate IDs stage',
    );
    await migrate.verify(source);
    final next = await SqliteCpdStore.openVerified(
      db,
      sourceId: SyntheticCpdMigration.sourceIdentity(source),
      documents: fixtures,
    );
    _same(
      (await next.loadAll()).map((entry) => entry.id).toList(),
      [7, 7],
      'duplicate IDs preserved',
    );
    _same(
      (await next.loadAll()).first.attachments,
      raw['attachments'],
      'unsupported evidence raw locator',
    );
    await _rejects<StateError>(() => next.setDeleted(7, true));
    _same(
      jsonDecode((await migrate.inspect(source))!.raw),
      source,
      'opaque unknown fields and raw row strings',
    );
    final created = await next.createAndSave(
      profession: 'Dentistry',
      date: DateTime(2024, 2, 29),
      title: 'Follow-up',
      details: '',
      hours: 0,
      minutes: 4,
      attachments: [],
    );
    _same(created.id, 8, 'future creates cannot reuse existing IDs');
  } finally {
    await db.close();
  }
  final blockedDb = await SqliteRecordingRepository.open(
    p.join(fixtures.path, 'blocked.sqlite'),
  );
  try {
    final migration = SyntheticCpdMigration(blockedDb, fixtures);
    final malformed = {
      ...source,
      'entries_json_list': [
        jsonEncode({...raw, 'date': '2024-02-30'}),
        jsonEncode({...raw, 'minutes': 1.5}),
        jsonEncode({...raw, 'date': '2024-02-29T00:00:00.000Z'}),
        '{"truncated":',
        unknown,
      ],
    };
    _same(
      await migration.stage(malformed),
      ImportStatus.blocked,
      'malformed source blocks projection',
    );
    final snapshot = (await migration.inspect(malformed))!;
    _same(jsonDecode(snapshot.raw), malformed, 'bad values retained exactly');
    _same(
      (jsonDecode(snapshot.metadata!)['issues'] as List)
          .where((issue) => issue['blocks'] == true)
          .length,
      4,
      'all blocked rows accounted for',
    );
    _same(await blockedDb.loadCollections(), [], 'no partial graph');
    await _rejects<StateError>(() => migration.verify(malformed));
  } finally {
    await blockedDb.close();
  }
  debugPrintSynchronously(
    'CPD_PARITY_OK: duplicate IDs and malformed data safeguards',
  );
}

Future<void> _separateRecovery(Directory scratch) async {
  final original = await Directory(p.join(scratch.path, 'Before')).create();
  final evidence = await _write(original, 'original.bin', [9, 4, 2]);
  final source = <String, Object?>{
    'professions': ['Dentistry'],
    'entries_json_list': [
      _entry(
        1,
        'Dentistry',
        attachments: [evidence.path, 'attachments/original.bin'],
      ).toJson(),
    ],
    'future_key': ['retained'],
  };
  final target = Directory(p.join(scratch.path, 'Backup'));
  await _rejects<InsufficientRecoveryStorage>(
    () => LegacyRecoverySnapshot.capture(
      legacyValues: source,
      documents: original,
      destination: target,
      availableBytes: (_) async => 3,
    ),
  );
  _check(!await target.exists(), 'low space leaves no recovery destination');
  _same(await evidence.readAsBytes(), [
    9,
    4,
    2,
  ], 'low space leaves source untouched');
  final copy = await LegacyRecoverySnapshot.capture(
    legacyValues: source,
    documents: original,
    destination: target,
    availableBytes: (_) async => 4 * 1024 * 1024,
  );
  await original.delete(recursive: true); // Only the synthetic source.
  final restored = Directory(p.join(scratch.path, 'After'));
  final recovered = await copy.restoreTo(restored);
  final recoveredValues = recovered.values;
  _same(recoveredValues, source, 'independent recovery raw values');
  _same(
    await File(p.join(restored.path, 'attachments/original.bin')).readAsBytes(),
    [9, 4, 2],
    'evidence recovered independently',
  );
  final db = await SqliteRecordingRepository.open(
    p.join(scratch.path, 'recovered.sqlite'),
  );
  try {
    final migration = SyntheticCpdMigration(
      db,
      restored,
      previousDocumentsPath: recovered.previousDocumentsPath,
    );
    _same(
      await migration.stage(recoveredValues),
      ImportStatus.staged,
      'stage recovered source',
    );
    await migration.verify(recoveredValues);
    final snapshot = (await migration.inspect(recoveredValues))!;
    _same(
      (jsonDecode(snapshot.metadata!)['originals'] as Map).length,
      2,
      'owned absolute paths rebase using the snapshot root',
    );
  } finally {
    await db.close();
  }
  debugPrintSynchronously(
    'CPD_PARITY_OK: separate snapshot recovery and capacity check',
  );
}

Future<void> _databaseFull(Directory scratch) async {
  final path = p.join(scratch.path, 'storage.sqlite');
  var db = await SqliteRecordingRepository.open(path);
  try {
    final source = <String, Object?>{
      'professions': ['Dentistry'],
      'entries_json_list': [
        _entry(1, 'Dentistry', details: 'x' * (512 * 1024)).toJson(),
      ],
    };
    var migration = SyntheticCpdMigration(db, scratch);
    await migration.capture(source);
    final native = await databaseFactory.openDatabase(path);
    final pages =
        (await native.rawQuery('PRAGMA page_count')).single.values.single
            as int;
    final constrained = await native.rawQuery('PRAGMA max_page_count = $pages');
    _same(constrained.single.values.single, pages, 'native SQLite page limit');
    await _rejects<RecordingStorageFull>(() => migration.stage(source));
    // The failure closes the poisoned connection. A fresh one matches a
    // device where the user freed space before retrying.
    db = await SqliteRecordingRepository.open(path);
    migration = SyntheticCpdMigration(db, scratch);
    _same(
      (await migration.inspect(source))!.status,
      ImportStatus.captured,
      'snapshot survives SQLite full',
    );
    _same(await db.loadCollections(), [], 'SQLite full rolls back destination');
    _same(
      await migration.stage(source),
      ImportStatus.staged,
      'SQL retry after capacity restored',
    );
    await migration.verify(source);
    debugPrintSynchronously('CPD_PARITY_OK: SQLITE_FULL rollback and retry');
  } finally {
    await db.close();
  }
}

Future<void> _upgrade(Directory scratch) async {
  final path = p.join(scratch.path, 'upgrade.sqlite');
  final repository = await SqliteRecordingRepository.open(path);
  final group = await repository.createCollection('Kept');
  await repository.close();
  final native = await databaseFactory.openDatabase(path);
  await native.execute('DROP TABLE host_state');
  await native.execute('PRAGMA user_version = 1');
  await native.close();
  final reopened = await SqliteRecordingRepository.open(path);
  try {
    _same(
      (await reopened.loadCollection(group.id))!.label,
      'Kept',
      'v1 data survives upgrade',
    );
    await reopened.saveHostValue('test', 'key', 'value');
    _same(await reopened.loadHostState('test'), {
      'key': 'value',
    }, 'v2 host metadata usable');
    debugPrintSynchronously('CPD_PARITY_OK: additive SQLite schema upgrade');
  } finally {
    await reopened.close();
  }
}

/// First start leaves a transaction open at a known write checkpoint. The
/// launcher force-stops the disposable process and then relaunches this target.
Future<void> _processExit() async {
  final support = await getApplicationSupportDirectory();
  final probe = await Directory(
    p.join(support.path, 'phase2-crash-probe'),
  ).create(recursive: true);
  final marker = File(p.join(probe.path, 'kill-ready'));
  final source = <String, Object?>{
    'professions': ['Dentistry'],
    'entries_json_list': [
      _entry(1, 'Dentistry', details: 'x' * 16384).toJson(),
    ],
  };
  final db = await SqliteRecordingRepository.open(
    p.join(probe.path, 'interrupted.sqlite'),
  );
  try {
    final migration = SyntheticCpdMigration(db, probe);
    if (!await marker.exists()) {
      await migration.capture(source);
      await db.transaction((tx) async {
        final staged = SyntheticCpdMigration(tx, probe);
        _same(
          await staged.stage(source),
          ImportStatus.staged,
          'uncommitted graph exists',
        );
        _same(
          (await tx.loadCollections()).length,
          1,
          'uncommitted collection exists',
        );
        await marker.writeAsString('before commit', flush: true);
        debugPrintSynchronously('CPD_PARITY_KILL_READY');
        await Future<void>.delayed(const Duration(minutes: 10));
        if (await marker.exists()) {
          throw StateError('Launcher did not terminate the waiting probe.');
        }
      });
      return;
    }
    _same(
      (await migration.inspect(source))!.status,
      ImportStatus.captured,
      'capture survives process termination',
    );
    _same(
      await db.loadCollections(),
      [],
      'actual process exit rolls back graph',
    );
    _same(
      await migration.stage(source),
      ImportStatus.staged,
      'restart retries',
    );
    await migration.verify(source);
    _same(
      await migration.stage(source),
      ImportStatus.verified,
      'restart does not create duplicate rows',
    );
    debugPrintSynchronously('CPD_PARITY_EXIT_PASS');
  } finally {
    await db.close();
  }
}

CpdEntry _entry(
  int id,
  String profession, {
  DateTime? day,
  String title = 'Example',
  String details = '',
  bool deleted = false,
  List<String> attachments = const [],
}) => CpdEntry(
  id: id,
  profession: profession,
  date: day ?? DateTime(2024, 2, 28),
  title: title,
  details: details,
  hours: 1,
  minutes: 5,
  attachments: attachments,
  deleted: deleted,
);

Future<File> _write(Directory docs, String name, List<int> bytes) async {
  final file = File(p.join(docs.path, 'attachments', name));
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes);
}

Uint8List _photo() => image.encodePng(
  image.fill(
    image.Image(width: 48, height: 36),
    color: image.ColorRgb8(120, 20, 180),
  ),
);

Future<Uint8List> _sourcePdf() async {
  final doc = pw.Document();
  for (final (index, page) in [
    PdfPageFormat.a6,
    PdfPageFormat.a6.landscape,
  ].indexed) {
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (_) => pw.Text('Evidence page ${index + 1}'),
      ),
    );
  }
  return doc.save();
}

void _same(Object? first, Object? second, String label) {
  _check(
    jsonEncode(_normalise(first)) == jsonEncode(_normalise(second)),
    label,
  );
}

Object? _normalise(Object? value) => switch (value) {
  Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _normalise(map[key]),
  },
  List values => values.map(_normalise).toList(),
  (int minutes, String cycle) => [minutes, cycle],
  Enum item => item.name,
  _ => value,
};

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> _rejects<T>(Future<Object?> Function() work) async {
  try {
    await work();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T.');
}
