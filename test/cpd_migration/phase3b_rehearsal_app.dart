import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/cpd_migration/legacy_write_gate.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/migration_report.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_rehearsal_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Run only in a disposable debug app. All records and paths are synthetic.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('This entry point is for debug builds.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  const scenario = String.fromEnvironment('CPD_REHEARSAL_SAMPLE');
  const locale = String.fromEnvironment('CPD_REHEARSAL_LOCALE');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: locale.isEmpty ? null : Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MigrationRehearsalPage(
        openAttempt: openSyntheticRehearsal,
        initialSample: switch (scenario) {
          'review' => RehearsalSample.review,
          'space' => RehearsalSample.lowStorage,
          _ => RehearsalSample.standard,
        },
        autoRun: scenario.isNotEmpty,
      ),
    ),
  );
}

Future<CpdMigrationCoordinator> openSyntheticRehearsal(
  RehearsalSample sample,
  Future<void> Function(MigrationReport) onCheckpoint,
) async {
  final root = await Directory.systemTemp.createTemp('cpd_phase3b_');
  final docs = await Directory(p.join(root.path, 'Documents')).create();
  final attachments = await Directory(
    p.join(docs.path, 'attachments'),
  ).create();
  await File(
    p.join(attachments.path, 'notes.txt'),
  ).writeAsString('Synthetic evidence');
  final row = {
    'id': 1,
    'profession': 'Education',
    'date': '2024-04-11',
    'title': 'Teaching workshop',
    'details': 'Planning and reflection',
    'hours': 1,
    'minutes': 15,
    'attachments': [
      'attachments/notes.txt',
      'attachments/older-certificate.pdf',
    ],
  };
  final raw = {
    'entries_json_list': [
      jsonEncode(row),
      if (sample == RehearsalSample.review) ...[
        jsonEncode({
          ...row,
          'title': 'Observation notes',
          'attachments': ['content://old-provider/record'],
        }),
        jsonEncode({...row, 'id': 2, 'date': '2024-02-30'}),
        jsonEncode({...row, 'id': 3, 'minutes': 12.5}),
      ],
    ],
    'professions': ['Education'],
    'targets_v1': '{"Education":{"minutes":600,"cycle":"year"}}',
  };
  var simulateLow = sample == RehearsalSample.lowStorage;
  return CpdMigrationCoordinator(
    workspace: Directory(p.join(root.path, 'attempt')),
    documents: docs,
    gate: LegacyWriteGate(),
    readLegacy: () async => raw,
    availableStorage: (directory) async {
      if (simulateLow) {
        simulateLow = false;
        return 1024;
      }
      return availableDeviceStorage(directory);
    },
    onCheckpoint: (report) async {
      await onCheckpoint(report);
      if (const bool.fromEnvironment('CPD_REHEARSAL_CAPTURE_PROGRESS') &&
          report.phase == MigrationPhase.verifying) {
        debugPrintSynchronously('CPD_PHASE3B_PROGRESS_SCREEN');
        await Future<void>.delayed(const Duration(seconds: 12));
      }
    },
  );
}
