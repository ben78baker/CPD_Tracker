import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

const _activeProfession = 'Community practice';
const _retiredProfession = 'Archived teaching';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=';

/// Run in an isolated Android application identity. Baseline and upgrade
/// APKs must share the same signing key and use different version codes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Signed upgrade probe'))),
    ),
  );
  try {
    final root = await getApplicationDocumentsDirectory();
    final photo = File('${root.path}/attachments/upgrade-photo.png');
    final certificate = File(
      '${root.path}/attachments/upgrade-certificate.pdf',
    );
    final proof = File('${root.path}/phase7b-legacy-baseline.json');
    final prefs = await SharedPreferences.getInstance();
    const baseline = bool.fromEnvironment('PHASE7B_BASELINE');
    final settings = SettingsStore.instance;
    final records = EntryRepository();

    Future<String> inventory() async => jsonEncode({
      'preferences': await readCpdLegacyPreferences(prefs),
      'photo': base64Encode(await photo.readAsBytes()),
      'certificate': base64Encode(await certificate.readAsBytes()),
    });

    if (baseline) {
      if ((await records.loadAll()).isNotEmpty || await proof.exists()) {
        throw StateError(
          'Baseline requires a fresh, isolated debug installation.',
        );
      }
      await photo.parent.create(recursive: true);
      await photo.writeAsBytes(base64Decode(_png), flush: true);
      final pdf = pw.Document()
        ..addPage(
          pw.Page(build: (_) => pw.Text('Synthetic preserved certificate')),
        );
      await certificate.writeAsBytes(await pdf.save(), flush: true);
      await settings.addProfession(_activeProfession);
      await settings.addProfession(_retiredProfession);
      await settings.setTarget(_activeProfession, minutes: 900, cycle: 'year');
      await settings.setReportLanguage(ReportLanguage.french);
      await settings.setLocaleCode('es');
      await settings.setAppAccent(AppAccent.teal);
      await settings.setDateFormat('yyyy-MM-dd');
      await settings.setWeekStart('saturday');
      await settings.setOnboardingComplete(true);
      await settings.setQrHintDismissed(true);
      await settings.saveProfile(
        name: 'Synthetic upgrade practitioner',
        company: 'Fixture practice',
      );

      await records.createAndSave(
        profession: _activeProfession,
        date: DateTime(2026, 10, 14),
        title: 'Clinical learning',
        details: 'Synthetic current entry',
        hours: 1,
        minutes: 30,
        attachments: [photo.path, certificate.path],
      );
      await records.createAndSave(
        profession: _activeProfession,
        date: DateTime(2021, 2, 5),
        title: 'Historical learning',
        details: 'Original historical words',
        hours: 0,
        minutes: 45,
        attachments: [certificate.path],
      );
      final deleted = await records.createAndSave(
        profession: _retiredProfession,
        date: DateTime(2023, 8, 10),
        title: 'Deleted learning',
        details: 'Retained for recovery',
        hours: 2,
        minutes: 20,
        attachments: [photo.path],
      );
      await records.setDeleted(deleted.id, true);
      await settings.softDeleteProfession(_retiredProfession);
      await proof.writeAsString(await inventory(), flush: true);
      debugPrintSynchronously('PHASE7B_SIGNED_BASELINE_PASS');
      return;
    }

    if (await inventory() != await proof.readAsString()) {
      throw StateError(
        'The raw legacy preferences or evidence changed across APK replacement.',
      );
    }
    final entries = await records.loadAll();
    if (entries.length != 3 ||
        entries
                .singleWhere((item) => item.title == 'Historical learning')
                .date
                .year !=
            2021 ||
        !entries
            .singleWhere((item) => item.title == 'Deleted learning')
            .deleted ||
        (await records.loadForProfession(_activeProfession)).length != 2 ||
        (await settings.getTarget(_activeProfession)) != (900, 'year') ||
        (await settings.getReportLanguage()) != ReportLanguage.french ||
        (await settings.getLocaleCode()) != 'es' ||
        !(await settings.loadDeletedProfessions()).contains(
          'Archived teaching',
        )) {
      throw StateError(
        'The upgraded legacy API did not return the expected records or preferences.',
      );
    }
    debugPrintSynchronously(
      'PHASE7B_SIGNED_UPGRADE_PASS: legacy preferences, targets, active, historical and deleted data, and exact PDF/photo bytes',
    );
  } on Object catch (error, stack) {
    debugPrintSynchronously('PHASE7B_SIGNED_FAIL: $error\n$stack');
    rethrow;
  }
}
