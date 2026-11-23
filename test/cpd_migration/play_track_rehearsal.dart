import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/migration_coordinator.dart';
import 'package:cpd_tracker/cpd_migration/rehearsal/migration_recovery_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/main.dart' as ordinary;
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/storage_authority.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Admission for the isolated Play tester's six-record legacy fixture.
bool matchesPlayFixture(Map<String, Object?> source, String token) {
  if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(token)) return false;
  const labels = {'Rehearsal alpha', 'Rehearsal beta'};
  final active = source['professions'];
  final deleted = source['deleted_professions'];
  final rows = source['entries_json_list'];
  if (active is! List ||
      active.length != labels.length ||
      !labels.containsAll(active) ||
      (deleted != null && (deleted is! List || deleted.isNotEmpty)) ||
      rows is! List ||
      rows.length != 6 ||
      rows.any((row) => row is! String)) {
    return false;
  }
  try {
    final records = rows.cast<String>().map(CpdEntry.fromJson).toList();
    final titles = {for (var i = 1; i <= 6; i++) 'CPD $token $i'};
    return titles.containsAll(records.map((row) => row.title)) &&
        records.map((row) => row.title).toSet().length == titles.length &&
        records.map((row) => row.id).toSet().length == titles.length &&
        records.every((row) => labels.contains(row.profession)) &&
        labels.every(
          (label) =>
              records.where((row) => row.profession == label).length == 3,
        ) &&
        records.where((row) => row.deleted).length == 1 &&
        records.any((row) => row.attachments.isNotEmpty);
  } on Object {
    return false;
  }
}

/// Alternate entry point for an explicitly approved Internal testing build.
/// Every other startup follows the ordinary application path.
Future<void> main() async {
  const token = String.fromEnvironment('CPD_PLAY_REHEARSAL_TOKEN');
  if (!kReleaseMode || !Platform.isAndroid || token.isEmpty) {
    ordinary.main();
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  if (p.basename(support.parent.path) != 'com.ingeneralapps.cpdtracker') {
    ordinary.main();
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  Future<Map<String, Object?>> read() => readCpdLegacyPreferences(preferences);
  final source = await read();
  final root = Directory(p.join(support.path, 'play-rehearsal'));
  final accent = await SettingsStore.instance.getAppAccent();
  if (!matchesPlayFixture(source, token)) {
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      ordinary.main();
    } else {
      runApp(
        MaterialApp(
          theme: AppTheme.forAccent(accent),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MigrationRecoveryPage(
            prepare: (_) async => const StartupAuthority(
              StoreAuthority.recovery,
              AuthorityReason.inconsistentEvidence,
              RecoveryCopyState.unchecked,
            ),
            onReady: () {},
          ),
        ),
      );
    }
    return;
  }

  final confirmed = ValueNotifier(false);
  final sealedSource = SyntheticCpdMigration.sourceIdentity(source);
  SqliteCpdStore? opened;
  runApp(
    MaterialApp(
      theme: AppTheme.forAccent(accent),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ValueListenableBuilder(
        valueListenable: confirmed,
        builder: (_, testing, _) => testing
            ? MigrationRecoveryPage(
                prepare: (progress) async {
                  if (await FileSystemEntity.type(
                        root.path,
                        followLinks: false,
                      ) ==
                      FileSystemEntityType.link) {
                    throw StateError('Unsafe rehearsal location.');
                  }
                  await root.create();
                  final documents = await getApplicationDocumentsDirectory();
                  final attempt = CpdMigrationCoordinator(
                    workspace: Directory(p.join(root.path, 'attempt')),
                    documents: documents,
                    readLegacy: read,
                    onCheckpoint: progress,
                  );
                  final before = await attempt.startup.inspect(
                    scope: AuthorityScope.rehearsal,
                    hasLegacyRecords: true,
                  );
                  if (SyntheticCpdMigration.sourceIdentity(await read()) !=
                      sealedSource) {
                    throw StateError('The confirmed rehearsal source changed.');
                  }
                  final authority = await attempt.recoverRehearsalStartup();
                  if (authority.store == StoreAuthority.recording) {
                    final receipt = await attempt.readReceipt();
                    if (receipt?.rehearsal != true ||
                        (before.store != StoreAuthority.recording &&
                            receipt?.sourceId != sealedSource)) {
                      throw StateError(
                        'Rehearsal receipt does not match the source.',
                      );
                    }
                    final repository = await SqliteRecordingRepository.open(
                      attempt.databasePath,
                      durableWrites: true,
                    );
                    try {
                      final store = await SqliteCpdStore.openVerified(
                        repository,
                        sourceId: receipt!.sourceId,
                        documents: documents,
                      );
                      if (before.store != StoreAuthority.recording) {
                        await store.verifyLegacyProjection(source);
                      }
                      opened = store;
                    } catch (_) {
                      await repository.close();
                      rethrow;
                    }
                  }
                  return authority;
                },
                onReady: () => runApp(ordinary.MyApp(dataStore: opened!)),
              )
            : Scaffold(
                appBar: AppBar(title: const Text('CPD internal rehearsal')),
                body: Center(
                  child: FilledButton(
                    onPressed: () => confirmed.value = true,
                    child: const Text(
                      'Start verified legacy fixture rehearsal',
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
