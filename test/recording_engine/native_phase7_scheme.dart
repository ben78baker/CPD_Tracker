import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'phase6_rehearsal_app.dart' show phase6Store;
import 'phase7_rehearsal_app.dart' show seedPhase7;
import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Verifying Phase 7'))),
    ),
  );
  final root = await Directory.systemTemp.createTemp('phase7_native_');
  final path = p.join(root.path, 'sandbox.sqlite');
  var db = await SqliteRecordingRepository.open(path);
  final bundle = nursingBundle;
  final originals = ManagedAttachmentFiles(root);
  try {
    final (first, second) = await seedPhase7(phase6Store(db), root);
    await phase6Store(db).saveSetting('locale', 'es');
    await phase6Store(db).saveSetting('reportLocale', 'fr');
    final periods = SchemePeriodStore(db);
    final original = await periods.load(first);
    _check(original.periods.length == 2, 'old period preserved');
    _check(
      (await periods.load(second)).selected == 'midwifery',
      'independent selections',
    );
    final previous = original.periods.firstWhere(
      (item) => item.id == 'previous',
    );
    await periods.select(first, previous);
    final conflict = SchemePeriod.create(
      bundle,
      id: previous.id,
      kind: PeriodKind.fixed,
      anchor: '2020-01-01',
    );
    var rejected = false;
    try {
      await periods.select(first, conflict);
    } on StateError {
      rejected = true;
    }
    _check(rejected, 'reject mutating a retained period');
    await db.close();
    db = await SqliteRecordingRepository.open(path);
    _check(
      (await SchemePeriodStore(db).load(first)).selected == previous.id,
      'selection survives reopen',
    );
    final history = await db.loadLayouts(first);
    await phase6Store(db).requireOwnedReport(history.last);
    final records = await db.loadRecords(first);
    final historical = await loadSchemeProgress(
      repository: db,
      bundle: bundle,
      period: previous,
      history: history,
      records: records,
      originals: originals,
    );
    _check(
      historical.progress.activities.isEmpty,
      'history excluded newer activities',
    );
    final report = await loadSchemeProgress(
      repository: db,
      bundle: bundle,
      period: rehearsalPeriod,
      history: history,
      records: records,
      originals: originals,
    );
    _check(
      report.progress.metrics['total'] ==
          (recorded: 360, complete: 240, eligible: 240),
      'recorded and eligible total',
    );
    _check(
      report.progress.metrics['participatory'] ==
          (recorded: 255, complete: 165, eligible: 165),
      'participatory total',
    );
    _check(
      report.progress.incomplete == 1 &&
          report.evidence.values.where((item) => item.available).length == 2,
      'evidence resolution',
    );
    final otherLayout = await db.loadLayouts(second);
    final other = adoptedRecipeFields(
      bundle,
      otherLayout.firstWhere((item) => item.templateId != null),
    );
    _check(
      other.values.toSet().every(
        (field) => !report.bindings.values.any((first) => first.id == field.id),
      ),
      'independent adopted field IDs',
    );
    final settings = await phase6Store(db).settings();
    final reportLocale = await ReportLocale.resolve(
      ReportLanguage.fromStored(settings['reportLocale']),
      AppLocalizationsEn(),
    );
    _check(
      settings['locale'] == 'es' &&
          reportLocale.strings.localeName == 'fr' &&
          bundle.country == 'United Kingdom',
      'report locale survives independently of app and scheme',
    );
    final pdf = await buildSchemeReport(
      bundle: bundle,
      progress: report.progress,
      bindings: report.bindings,
      evidence: report.evidence,
      strings: AppLocalizationsEn(),
      practitioner: 'Synthetic practitioner',
      reportLocale: reportLocale,
    );
    _check(
      String.fromCharCodes(pdf.take(5)) == '%PDF-',
      'native scheme report',
    );
    debugPrintSynchronously(
      'PHASE7_NATIVE_PASS: independent periods, restart, originals, 360/255 recorded, 240/165 eligible, scheme PDF',
    );
  } catch (error, stack) {
    debugPrintSynchronously('PHASE7_NATIVE_FAIL: $error\n$stack');
    rethrow;
  } finally {
    await db.close();
    await root.delete(recursive: true);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
