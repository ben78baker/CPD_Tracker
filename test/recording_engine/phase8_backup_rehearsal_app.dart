import 'dart:io';

import 'package:cpd_tracker/cpd_backup/backup_page.dart';
import 'package:cpd_tracker/cpd_backup/cpd_portable_backup.dart';
import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine_storage/protected_recording_store.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'phase6_rehearsal_app.dart' show phase6Store;
import 'phase7_rehearsal_app.dart' show seedPhase7;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final root = await Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'phase8-ui-rehearsal',
    ),
  ).create(recursive: true);
  final live = RecordingWorkspace(Directory(p.join(root.path, 'live')));
  final recovery = Directory(p.join(root.path, 'recovery'));
  final portable = cpdPortableBackup(availableDeviceStorage);
  final host = ProtectedRecordingStore(
    live: live,
    recovery: recovery,
    backup: SqliteRecordingBackup(available: availableDeviceStorage),
  );
  if (!await live.directory.exists()) {
    await live.originals.create(recursive: true);
    final db = await SqliteRecordingRepository.open(live.databasePath);
    try {
      await seedPhase7(phase6Store(db), live.originals);
    } finally {
      await db.close();
    }
    await host.enrol();
  }
  File? created;
  const useFixture = bool.fromEnvironment('PHASE8_UI_FIXTURE');
  const language = String.fromEnvironment('PHASE8_LOCALE', defaultValue: 'en');
  const accent = String.fromEnvironment(
    'PHASE8_ACCENT',
    defaultValue: 'purple',
  );
  runApp(
    MaterialApp(
      locale: Locale(language),
      theme: AppTheme.forAccent(AppAccent.fromStorage(accent)),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      debugShowCheckedModeBanner: false,
      home: BackupPage(
        create: () async {
          final destination = await root.createTemp('export-');
          final file = File(p.join(destination.path, 'CPD.recordingbackup'));
          final result = await host.createPortable(portable, file);
          created = file;
          return (file: file, inspection: result);
        },
        chooseAndVerify: () async {
          final File? file;
          if (useFixture) {
            file = created;
          } else {
            final picked = await FilePicker.platform.pickFiles();
            final path = picked?.files.single.path;
            file = path == null ? null : File(path);
          }
          if (file == null) return null;
          final inspection = await portable.inspect(file);
          final check = await root.createTemp('validation-');
          try {
            await portable.restore(
              source: file,
              inspection: inspection,
              destination: Directory(p.join(check.path, 'candidate')),
            );
          } finally {
            await check.delete(recursive: true);
          }
          return (file: file, inspection: inspection);
        },
        share: (file, anchor) async {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: 'application/octet-stream')],
              sharePositionOrigin: anchor,
            ),
          );
        },
        prepareReplacement: (input) async {
          final session = await root.createTemp('replacement-');
          await host.prepareReplacement(
            portable: portable,
            source: input.file,
            inspection: input.inspection,
            destination: Directory(p.join(session.path, 'candidate')),
          );
        },
      ),
    ),
  );
}
