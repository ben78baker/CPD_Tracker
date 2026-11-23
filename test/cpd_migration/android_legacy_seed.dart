import 'dart:io';

import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/main.dart' as legacy;
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image;
import 'package:pdf/widgets.dart' as pdf;

/// Build this entry point against 425e6bb in an isolated checkout.
Future<void> main() async {
  if (kReleaseMode ||
      !Platform.isAndroid ||
      !const bool.fromEnvironment('CPD_ANDROID_SEED_LEGACY')) {
    throw UnsupportedError('Use the authorised development legacy build.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final entries = EntryRepository();
  final settings = SettingsStore.instance;
  if ((await entries.loadAll()).isNotEmpty ||
      (await settings.loadProfessions()).isNotEmpty) {
    throw StateError('Legacy seed requires an empty recording store.');
  }

  const professions = [
    'Community Nursing',
    'Electrical Maintenance',
    'Dental Practice',
    'Archived Practice',
  ];
  for (final (index, name) in professions.indexed) {
    await settings.addProfession(name);
    await settings.setTarget(name, minutes: 180 + index * 60, cycle: 'year');
  }
  await settings.setAppAccent(AppAccent.teal);
  await settings.setWeekStart('saturday');
  await settings.setDateFormat('yyyy-MM-dd');
  await settings.setLocaleCode('en');
  await settings.setQrHintDismissed(true);
  await settings.saveProfile(name: 'Rehearsal User', company: 'Fixture Group');

  final scratch = await Directory.systemTemp.createTemp('cpd-legacy-media');
  try {
    final pages = pdf.Document();
    for (var page = 1; page <= 2; page++) {
      pages.addPage(
        pdf.Page(build: (_) => pdf.Text('Legacy evidence page $page')),
      );
    }
    final certificate = await File(
      '${scratch.path}/certificate.pdf',
    ).writeAsBytes(await pages.save());
    final photo = image.Image(width: 32, height: 32);
    image.fill(photo, color: image.ColorRgb8(20, 130, 90));
    final photograph = await File(
      '${scratch.path}/photo.jpg',
    ).writeAsBytes(image.encodeJpg(photo));
    final note = await File(
      '${scratch.path}/assessment.txt',
    ).writeAsString('Legacy assessment evidence.');
    final references = [
      await copyLocalToAppDir(certificate.path),
      await copyLocalToAppDir(photograph.path),
      await copyLocalToAppDir(note.path),
    ];

    for (var row = 0; row < 12; row++) {
      final record = await entries.createAndSave(
        profession: professions[row % professions.length],
        date: DateTime(2024 + row % 3, 1 + row % 10, 1 + row),
        title: 'Legacy rehearsal activity ${row + 1}',
        details: row.isEven
            ? 'Réflexion – práctica'
            : 'Learning and reflection',
        hours: row % 3,
        minutes: 5 * (row + 1) % 60,
        attachments: switch (row) {
          0 => [references[0], references[1], 'https://example.com/legacy-cpd'],
          1 => [references[2]],
          7 => [references[0]],
          _ => [],
        },
      );
      if (row == 4 || row == 7) await entries.setDeleted(record.id, true);
    }
    await settings.softDeleteProfession(professions.last);
    await settings.setOnboardingComplete(true);
  } finally {
    await scratch.delete(recursive: true);
  }
  debugPrintSynchronously('CPD_ANDROID_LEGACY_READY');
  legacy.main();
}
