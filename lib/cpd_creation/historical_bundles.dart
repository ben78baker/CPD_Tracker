import '../recording_engine/models.dart';
import '../recording_engine/template_review.dart';
import '../recording_engine_storage/portable_archive.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'scheme_period_store.dart';
import 'template_bundle.dart';

/// The installed catalogue is useful at adoption time. The retained envelope
/// supplies the exact rules for historical reports on a different installation.
class HistoricalCpdBundles {
  const HistoricalCpdBundles();
  static const _namespace = 'cpd.scheme.bundle-history';

  String _key(String id, int version, int rules) => '$id:$version:$rules';

  Future<void> retain(
    SqliteRecordingRepository tx,
    ProfessionTemplateBundle bundle,
  ) async {
    final key = _key(
      bundle.recipe.id,
      bundle.recipe.version,
      bundle.ruleVersion,
    );
    final encoded = bundle.encode();
    final previous = (await tx.loadHostState(_namespace))[key];
    if (previous != null && previous != encoded) {
      throw StateError('A retained reporting rule version is immutable.');
    }
    await tx.saveHostValue(_namespace, key, encoded);
  }

  Future<ProfessionTemplateBundle?> read(
    SqliteRecordingRepository tx,
    String id,
    int version,
    int rules,
  ) async {
    final data = (await tx.loadHostState(_namespace))[_key(id, version, rules)];
    return data == null ? null : ProfessionTemplateBundle.decode(data);
  }

  Future<void> verify(SqliteRecordingRepository tx) async {
    final byRecipe = <(String, int), Set<int>>{};
    for (final entry in (await tx.loadHostState(_namespace)).entries) {
      final bundle = ProfessionTemplateBundle.decode(entry.value);
      final recipe = bundle.recipe;
      final pin = (recipe.id, recipe.version);
      if (entry.key != _key(recipe.id, recipe.version, bundle.ruleVersion)) {
        _missing();
      }
      final stored = await tx.loadTemplate(recipe.id, recipe.version);
      if (stored == null ||
          encodeTemplateDefinition(stored) !=
              encodeTemplateDefinition(recipe)) {
        _missing();
      }
      byRecipe.putIfAbsent(pin, () => {}).add(bundle.ruleVersion);
    }
    for (final collection in await tx.loadCollections()) {
      final layouts = await tx.loadLayouts(collection.id);
      final adopted = <(String, int)>{};
      for (final layout in layouts) {
        if (layout.templateId case final id?) {
          adopted.add((id, layout.templateVersion!));
          final recipe = await tx.loadTemplate(id, layout.templateVersion!);
          if (recipe?.origin == TemplateOrigin.bundled &&
              !byRecipe.containsKey((id, layout.templateVersion!))) {
            _missing();
          }
        }
      }
      final saved = await SchemePeriodStore(tx).load(collection.id);
      if (saved.selected != null &&
          !saved.periods.any((period) => period.id == saved.selected)) {
        _missing();
      }
      for (final period in saved.periods) {
        final pin = (period.templateId, period.templateVersion);
        if (!adopted.contains(pin) ||
            !(byRecipe[pin]?.contains(period.ruleVersion) ?? false)) {
          _missing();
        }
      }
    }
  }

  Never _missing() => throw const BackupException(
    BackupProblem.integrity,
    'A historical CPD rule or template is missing or inconsistent.',
  );
}
