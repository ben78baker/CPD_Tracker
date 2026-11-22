import 'dart:io';

import 'package:cpd_tracker/cpd_backup/backup_cache.dart';
import 'package:cpd_tracker/cpd_backup/cpd_collection_backup.dart';
import 'package:cpd_tracker/cpd_backup/profession_backup_page.dart';
import 'package:cpd_tracker/cpd_migration/device_storage_capacity.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/original_directory_sync.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'phase6_rehearsal_app.dart';
import 'phase7_rehearsal_app.dart' show seedPhase7;

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Use a disposable debug app.');
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'profession-backup-rehearsal',
    ),
  ).create(recursive: true);
  final platformCache = await getTemporaryDirectory();
  final cache = Directory(p.join(platformCache.path, 'profession-backups'));
  await resetBackupScratch(cache);
  // This disposable app has no unrelated picker operations. Android creates
  // timestamped private copies under this plugin-owned cache directory.
  final pickerCache = Platform.isAndroid
      ? Directory(p.join(platformCache.path, 'file_picker'))
      : Directory.systemTemp;
  if (Platform.isAndroid) await resetBackupScratch(pickerCache);
  final workspace = RecordingWorkspace(root);
  await workspace.originals.create();
  final files = ManagedAttachmentFiles(
    workspace.originals,
    syncDirectory: syncOriginalDirectory,
  );
  final backups = ProfessionBackupActions(
    backups: cpdCollectionBackup(availableDeviceStorage),
    temporary: cache,
    originals: files,
    pick: () async {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      return path == null
          ? null
          : BackupInputFile(
              File(path),
              cacheRoot: pickerCache,
              nestedCache: Platform.isAndroid,
            );
    },
    share: (file, origin) async {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          sharePositionOrigin: origin,
        ),
      );
      if (Platform.isAndroid && result.status == ShareResultStatus.dismissed) {
        await _clearAndroidHandoff(platformCache, p.basename(file.path));
      }
    },
  );
  if (Platform.isAndroid) {
    for (final name in [
      'Profession.recordingbackup',
      'Protected.recordingbackup',
    ]) {
      await _clearAndroidHandoff(platformCache, name);
    }
  }
  runApp(
    Phase6App(
      phase7: true,
      originals: files,
      backups: backups,
      open: () async {
        final db = await SqliteRecordingRepository.open(
          workspace.databasePath,
          durableWrites: true,
        );
        await backups.backups.reconcileInterruptedRestores(db, files.root);
        final store = phase6Store(db);
        if (const bool.fromEnvironment('CPD_BACKUP_SAMPLES') &&
            (await db.loadCollections()).isEmpty) {
          await seedPhase7(store, files.root);
        }
        return store;
      },
    ),
  );
}

Future<void> _clearAndroidHandoff(Directory cache, String name) {
  final owner = Directory(p.join(cache.path, 'share_plus'));
  return BackupInputFile(
    File(p.join(owner.path, name)),
    cacheRoot: owner,
  ).dispose();
}
