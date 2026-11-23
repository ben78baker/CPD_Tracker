import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cpd_tracker/add_entry_page.dart';
import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_records_page.dart';
import 'package:cpd_tracker/deleted_records_page.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:cpd_tracker/utils/csv_exporter.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart';
import 'package:cpd_tracker/utils/record_search.dart';
import 'package:cpd_tracker/widgets/home_shell.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:cpd_tracker/widgets/record_card.dart';
import 'package:cpd_tracker/widgets/tactile_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'native_rehearsal_media.dart' show RehearsalMedia;

typedef XrLog = void Function(String event, [Map<String, Object?> data]);

const _profession = 'Migration verification';
const _title = 'XR verification record';
const _detail = 'Edited after the SQLite migration';

/// Invoke the same callbacks as the visible controls after the actual screens
/// have rendered on the phone. The write probe exercises their shared store.
Future<void> xrScreenProbe(SqliteCpdStore store, XrLog log) async {
  final homeTile = await _visible<ProfessionCard>();
  (homeTile.widget as ProfessionCard).onView();
  final profession = await _visible<CpdRecordsPage>();
  _check(
    identical((profession.widget as CpdRecordsPage).recordStore, store),
    'Profession navigation did not use SQLite.',
  );
  await Navigator.of(profession).maybePop();

  final home = (await _visible<HomeShell>()).widget as HomeShell;
  home.onSearch();
  final search =
      (await _visible<TextField>(
            (field) =>
                field.decoration?.hintText ==
                'Search all professions and records',
          )).widget
          as TextField;
  search.controller!.text = 'edited after';
  search.onChanged!('edited after');
  final result = (await _visible<TactileButton>()).widget as TactileButton;
  result.onPressed!();
  final row =
      (await _visible<RecordCard>((row) => row.entry.title == _title)).widget
          as RecordCard;
  row.onEdit!();
  final editor = await _visible<AddEntryPage>();
  final page = editor.widget as AddEntryPage;
  _check(
    identical(page.recordStore, store) &&
        page.existingEntry?.details == _detail &&
        page.existingEntry?.attachments.length == 3,
    'The edit screen did not open the SQLite record and evidence.',
  );
  log('ui_edit_route', {'source': 'globalSearch', 'evidence': 3});
  await Navigator.of(editor).maybePop();
  await Navigator.of(await _visible<CpdRecordsPage>()).maybePop();
  await Navigator.of(await _visible<TextField>()).maybePop();
  ((await _visible<HomeShell>()).widget as HomeShell).onMenuSelected(
    'deleted_records',
  );
  final deleted = await _visible<DeletedRecordsPage>();
  final deletedId = (await store.loadDeleted()).single.id;
  await _visible<Widget>(
    (widget) => widget.key == ValueKey('restore-record-$deletedId'),
  );
  _check(
    identical((deleted.widget as DeletedRecordsPage).dataStore, store),
    'The deleted-records screen did not use SQLite.',
  );
  log('ui_routes_pass', {'deletedRecoveryControls': 1});
  await Navigator.of(deleted).maybePop();
}

Future<Element> _visible<T extends Widget>([bool Function(T)? matches]) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 8)) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is T &&
          (matches?.call(widget) ?? true) &&
          ModalRoute.of(element)?.isCurrent == true) {
        found = element;
      } else {
        element.visitChildren(visit);
      }
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    if (found != null) return found!;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw XrProbeFailure('Visible screen control timed out ($T).');
}

Future<void> xrWorkflowProbe(
  SqliteCpdStore store,
  SqliteRecordingRepository repository,
  Directory root,
  Future<Map<String, Object?>> Function() readLegacy,
  Map<String, Object?> original,
  XrLog log, {
  required bool write,
}) async {
  final timer = Stopwatch()..start();
  try {
    await LegacyWriteGate.instance.write(() async {});
    throw const FormatException('Legacy record writer remained open.');
  } on StateError {
    log('legacy_writer_sealed');
  }
  final baseline = (original['entries_json_list'] as List)
      .cast<String>()
      .map(CpdEntry.fromJson)
      .toList();
  List<CpdEntry> probes(List<CpdEntry> rows) => rows
      .where((row) => row.title == _title && row.profession == _profession)
      .toList();
  var entries = await store.loadAll();
  if (write && probes(entries).isEmpty) {
    await store.addProfession(_profession);
    final fixture = await root.createTemp('probe-originals-');
    try {
      final media = await RehearsalMedia.create(fixture);
      final attachments = [
        await copyLocalToAppDir(media.photo.path),
        await copyLocalToAppDir(media.pdf.path),
      ];
      await store.createAndSave(
        profession: _profession,
        date: DateTime(2026, 11, 20),
        title: _title,
        details: 'Initial entry',
        hours: 1,
        minutes: 15,
        attachments: [
          ...attachments,
          'https://example.com/cpd-xr-verification',
        ],
      );
      final bytesMatch =
          await backupDigest(media.photo) ==
              await backupDigest(
                File(await resolveStoredPath(attachments.first)),
              ) &&
          await backupDigest(media.pdf) ==
              await backupDigest(
                File(await resolveStoredPath(attachments.last)),
              );
      _check(bytesMatch, 'Evidence bytes changed on import.');
    } finally {
      await fixture.delete(recursive: true);
    }
    entries = await store.loadAll();
  }
  var record = probes(entries).single;
  if (write) {
    await store.updateEntry(
      CpdEntry(
        id: record.id,
        profession: record.profession,
        date: record.date,
        title: record.title,
        details: _detail,
        hours: 1,
        minutes: 30,
        attachments: record.attachments,
      ),
    );
    await store.setDeleted(record.id, true);
    _check(
      (await store.loadDeleted()).any((row) => row.id == record.id),
      'Record did not enter deleted recovery.',
    );
    await store.softDeleteProfession(_profession);
    _check(
      (await store.loadDeletedProfessions()).contains(_profession),
      'Deleted profession unavailable.',
    );
    await store.restoreRecord(record.id, recoverProfession: true);
    await store.setTarget(_profession, minutes: 240, cycle: 'month');
  }
  entries = await store.loadAll();
  record = probes(entries).single;
  final expectedOriginal = baseline.map((entry) => entry.toJson()).toList();
  final remainingOriginal = entries
      .where((entry) => entry.id != record.id)
      .map((entry) => entry.toJson())
      .toList();
  _check(
    jsonEncode(expectedOriginal) == jsonEncode(remainingOriginal),
    'Original records changed during workflow checks.',
  );
  _check(
    encodeLegacySnapshot(original) == encodeLegacySnapshot(await readLegacy()),
    'Legacy recording preferences changed.',
  );
  _check(
    (await store.loadActiveProfessions()).contains(_profession),
    'Profession navigation unavailable.',
  );
  final visible = await store.loadForProfession(_profession);
  _check(
    RecordSearch.groupByProfession(
          visible,
          'edited after',
        )[_profession]?.single.id ==
        record.id,
    'Edited record missing from search.',
  );
  _check(
    !record.deleted &&
        record.minutes == 30 &&
        (await store.getTarget(_profession)) == (240, 'month'),
    'Record or target did not persist.',
  );
  _check(
    (await store.sumMinutesForRange(
          _profession,
          DateTime(2026, 11, 1),
          DateTime(2026, 12, 1),
        )) ==
        90,
    'CPD duration parity failed.',
  );
  _check(
    (await repository.loadAllRecords()).length == entries.length,
    'SQLite graph and projection differ.',
  );
  final managed = <String>[];
  for (final reference in record.attachments.where((value) => !isUrl(value))) {
    managed.add(await backupDigest(File(await resolveStoredPath(reference))));
  }
  final digestFile = File(p.join(root.path, 'new-evidence.sha256.json'));
  if (write) {
    await digestFile.writeAsString(jsonEncode(managed), flush: true);
  } else {
    _check(
      jsonEncode(managed) == await digestFile.readAsString(),
      'Evidence changed after restart.',
    );
  }
  log('workflow_store_pass', {
    'newRecordId': record.id,
    'records': entries.length,
    'deleted': (await store.loadDeleted()).length,
    'newOriginals': managed.length,
    'legacyUnchanged': true,
    'write': write,
    'elapsedWorkMs': timer.elapsedMilliseconds,
  });
  if (!write) return;

  final exportRoot = await root.createTemp('exports-');
  final selection = CpdExportSelection.fromVisibleRecords(
    profession: _profession,
    range: DateTimeRange(start: record.date, end: record.date),
    visibleRecords: visible,
  );
  final strings = AppLocalizationsEn();
  const dateFormat = 'dd/MM/yyyy';
  final csv = buildCpdCsv(
    selection: selection,
    dateFormat: dateFormat,
    texts: strings,
  ).text;
  _check(
    csv.contains(_title) && csv.contains(_detail),
    'CSV missed persisted values.',
  );
  await File(
    p.join(exportRoot.path, 'verification.csv'),
  ).writeAsString(csv, flush: true);
  final asset = await rootBundle.load('assets/icon/1024x1024_app_icon.png');
  final icon = asset.buffer.asUint8List(
    asset.offsetInBytes,
    asset.lengthInBytes,
  );
  final fonts = CpdPdfFonts.standard();
  Future<Directory> output(String revision) =>
      Directory(p.join(exportRoot.path, revision)).create();
  final plain = await buildRecordsPdf(
    selection: selection,
    dateFormat: dateFormat,
    outputDirectory: await output('text'),
    fonts: fonts,
    appIconBytes: icon,
  );
  final withEvidence = await buildRecordsPdfWithEvidenceArtifacts(
    selection: selection,
    dateFormat: dateFormat,
    outputDirectory: await output('evidence'),
    fonts: fonts,
    appIconBytes: icon,
  );
  final zip = await buildRecordsBundleZip(
    selection: selection,
    dateFormat: dateFormat,
    outputDirectory: await output('bundle'),
    fonts: fonts,
    appIconBytes: icon,
  );
  final archive = ZipDecoder().decodeBytes(
    await zip.readAsBytes(),
    verify: true,
  );
  for (final reference in record.attachments.where((value) => !isUrl(value))) {
    final originalFile = File(await resolveStoredPath(reference));
    final member = archive.files.singleWhere(
      (file) => file.isFile && p.basename(file.name) == p.basename(reference),
    );
    _check(
      listEquals(member.content, await originalFile.readAsBytes()),
      'A ZIP evidence file differs from its stored original.',
    );
  }
  _check(
    archive.files
                .where((file) => file.isFile && file.name.endsWith('.pdf'))
                .length >=
            2 &&
        archive.files.any((file) => file.isFile && file.name.endsWith('.png')),
    'ZIP omitted the report or evidence originals.',
  );
  Future<int> pages(File file) async {
    var count = 0;
    await for (final _ in Printing.raster(
      await file.readAsBytes(),
      dpi: PdfPageFormat.inch,
    )) {
      count++;
    }
    return count;
  }

  final plainPages = await pages(plain);
  final evidencePages = await pages(withEvidence.pdfFile);
  _check(
    plainPages >= 1 && evidencePages > plainPages,
    'Evidence PDF did not render extra pages.',
  );
  final evidencePdf = latin1.decode(await withEvidence.pdfFile.readAsBytes());
  _check(
    evidencePdf.contains('/URI') &&
        evidencePdf.contains('https://example.com/cpd-xr-verification'),
    'Evidence PDF is missing its link annotation.',
  );
  final missing = CpdExportSelection.fromVisibleRecords(
    profession: _profession,
    range: selection.range,
    visibleRecords: [
      CpdEntry(
        id: record.id,
        profession: record.profession,
        date: record.date,
        title: record.title,
        attachments: ['attachments/xr-probe-missing.pdf'],
        details: record.details,
        hours: record.hours,
        minutes: record.minutes,
      ),
    ],
  );
  CpdPdfPresentation? missingPresentation;
  await buildRecordsPdf(
    selection: missing,
    dateFormat: dateFormat,
    outputDirectory: await output('missing'),
    fonts: fonts,
    appIconBytes: icon,
    evidenceMode: CpdPdfEvidenceMode.embeddedImages,
    onPresentationPrepared: (value) => missingPresentation = value,
  );
  _check(
    missingPresentation?.records.single.evidence.single.isMissing == true,
    'The report did not flag missing evidence.',
  );
  final supplementaryOriginal = await File(
    p.join(exportRoot.path, 'xr-evidence.txt'),
  ).writeAsString('Unrenderable evidence fixture');
  final supplementary = CpdExportSelection.fromVisibleRecords(
    profession: _profession,
    range: selection.range,
    visibleRecords: [
      CpdEntry(
        id: record.id,
        profession: record.profession,
        date: record.date,
        title: record.title,
        details: record.details,
        hours: record.hours,
        minutes: record.minutes,
        attachments: [supplementaryOriginal.path],
      ),
    ],
  );
  final conditional = await buildRecordsPdfWithEvidenceArtifacts(
    selection: supplementary,
    dateFormat: dateFormat,
    outputDirectory: await output('conditional'),
    fonts: fonts,
    appIconBytes: icon,
    attachmentPathResolver: (path) async => path,
  );
  _check(
    !withEvidence.includesOriginalEvidenceZip &&
        conditional.originalBundleEvidenceCount == 1 &&
        conditional.originalEvidenceZip != null,
    'Conditional ZIP decisions did not match rendered evidence.',
  );
  final extra = ZipDecoder().decodeBytes(
    await conditional.originalEvidenceZip!.readAsBytes(),
    verify: true,
  );
  _check(
    listEquals(
      extra.files
          .singleWhere((file) => file.name.endsWith('xr-evidence.txt'))
          .content,
      await supplementaryOriginal.readAsBytes(),
    ),
    'Conditional ZIP did not preserve its original file.',
  );
  log('exports_pass', {
    'csvBytes': utf8.encode(csv).length,
    'plainPdfPages': plainPages,
    'evidencePdfPages': evidencePages,
    'zipBytes': await zip.length(),
    'zipFiles': archive.files.where((file) => file.isFile).length,
    'conditionalZipPass': true,
    'missingEvidenceMarked': true,
    'linkAnnotation': true,
    'elapsedWorkMs': timer.elapsedMilliseconds,
  });
}

class XrProbeFailure implements Exception {
  const XrProbeFailure(this.check);

  final String check;
}

void _check(bool condition, String message) {
  if (!condition) throw XrProbeFailure(message);
}
