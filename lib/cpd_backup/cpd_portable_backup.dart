import '../cpd_creation/historical_bundles.dart';
import '../cpd_creation/profession_creation_store.dart';
import '../cpd_creation/template_evaluation.dart';
import '../cpd_migration/startup_migration_authority.dart';
import '../recording_engine_storage/portable_archive.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';

/// Portable identity and report provenance belong to the user. Store grants
/// and a migration handoff belong to the installation that verified them.
SqliteRecordingBackup cpdPortableBackup(AvailableStorage available) =>
    SqliteRecordingBackup(
      available: available,
      includeHostRow: (namespace, key) =>
          namespace != ProfessionCreationStore.grantsNamespace &&
          namespace != TemplateEvaluationLedger.namespace &&
          (namespace != migrationAuthorityNamespace ||
              key != migrationAuthorityKey),
      verifyHost: const HistoricalCpdBundles().verify,
    );
