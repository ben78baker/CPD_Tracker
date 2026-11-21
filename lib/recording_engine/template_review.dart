import 'dart:convert';

import 'models.dart';

/// A preview only. Its stable keys identify published recipe fields and its
/// instance IDs identify local additions. It never writes or merges layouts.
class TemplateReview {
  TemplateReview._({
    required this.added,
    required this.retired,
    required this.changed,
    required this.localFields,
    required this.modifiedLocally,
    required this.removedLocally,
    required this.publisherReordered,
    required this.localReordered,
    required this.presentationChanged,
  });

  final List<String> added;
  final List<String> retired;
  final List<String> changed;
  final List<String> localFields;
  final List<String> modifiedLocally;
  final List<String> removedLocally;
  final bool publisherReordered;
  final bool localReordered;
  final bool presentationChanged;

  /// The Phase 4 repository preserves the exact adoption in an immutable
  /// revision. Adopted fields have fresh IDs and the original recipe's order.
  factory TemplateReview.compare({
    required TemplateVersion original,
    required LayoutRevision adoption,
    required LayoutRevision installed,
    required TemplateVersion update,
  }) {
    if (original.id != update.id ||
        original.version >= update.version ||
        adoption.collectionId != installed.collectionId ||
        adoption.version > installed.version ||
        adoption.templateId != original.id ||
        adoption.templateVersion != original.version ||
        installed.templateId != adoption.templateId ||
        installed.templateVersion != adoption.templateVersion ||
        adoption.fields.length != original.fields.length) {
      throw ArgumentError(
        'Incompatible template versions or layout provenance.',
      );
    }
    final baseline = <String, LayoutField>{};
    for (final (index, field) in original.fields.indexed) {
      final local = adoption.fields[index];
      if (!_matches(field, local)) {
        throw ArgumentError('The original adoption revision is required.');
      }
      baseline[field.id] = local;
    }
    final recipe = {for (final field in original.fields) field.id: field};
    final incoming = {for (final field in update.fields) field.id: field};
    final current = {for (final field in installed.fields) field.id: field};
    final initialIds = baseline.values.map((field) => field.id).toSet();
    final currentRecipeKeys = [
      for (final local in installed.fields)
        for (final entry in baseline.entries)
          if (entry.value.id == local.id) entry.key,
    ];
    return TemplateReview._(
      added: List.unmodifiable(
        incoming.keys.where((id) => !recipe.containsKey(id)),
      ),
      retired: List.unmodifiable(
        recipe.keys.where((id) => !incoming.containsKey(id)),
      ),
      changed: List.unmodifiable(
        recipe.keys.where(
          (id) =>
              incoming.containsKey(id) && !_matches(recipe[id]!, incoming[id]!),
        ),
      ),
      localFields: List.unmodifiable(
        current.keys.where((id) => !initialIds.contains(id)),
      ),
      modifiedLocally: List.unmodifiable(
        baseline.keys.where(
          (id) =>
              current.containsKey(baseline[id]!.id) &&
              !_matches(baseline[id]!, current[baseline[id]!.id]!),
        ),
      ),
      removedLocally: List.unmodifiable(
        baseline.keys.where((id) => !current.containsKey(baseline[id]!.id)),
      ),
      publisherReordered: _orderChanged(recipe.keys, incoming.keys),
      localReordered: _orderChanged(recipe.keys, currentRecipeKeys),
      presentationChanged:
          original.label != update.label ||
          encodeSettings(original.settingsToJson()) !=
              encodeSettings(update.settingsToJson()),
    );
  }

  static bool _matches(LayoutField recipe, LayoutField installed) =>
      encodeSettings(recipe.reidentify(installed.id).toJson()) ==
      encodeSettings(installed.toJson());

  static bool _orderChanged(Iterable<String> before, Iterable<String> after) =>
      before.where(after.contains).join('\u0000') !=
      after.where(before.contains).join('\u0000');
}

/// A deterministic, inspectable template fixture. Record values, asset
/// originals, collection IDs, rules and purchase information are outside it.
String encodeTemplateDefinition(
  TemplateVersion template, {
  int? maximumFields,
}) {
  if (maximumFields != null && template.fields.length > maximumFields) {
    throw ArgumentError('Too many active fields.');
  }
  final definitions = <(String, int), String>{};
  for (final field in template.fields) {
    final definition = field.definition;
    final key = (definition.id, definition.version);
    final payload = encodeSettings(definition.toJson());
    if (definitions.putIfAbsent(key, () => payload) != payload) {
      throw ArgumentError('Conflicting definition versions.');
    }
  }
  final definition = const JsonEncoder.withIndent('  ').convert({
    'formatVersion': 1,
    'id': template.id,
    'version': template.version,
    'label': template.label,
    'settings': _ordered(template.settingsToJson()),
    'fields': [for (final field in template.fields) _ordered(field.toJson())],
  });
  return '$definition\n';
}

TemplateVersion decodeTemplateDefinition(String raw, {int? maximumFields}) {
  final payload = jsonDecode(raw) as Map<String, dynamic>;
  if (payload['formatVersion'] != 1) {
    throw const FormatException('Unknown template format.');
  }
  final settings = payload['settings'] as Map<String, dynamic>;
  final recipe = TemplateVersion(
    id: payload['id'] as String,
    version: payload['version'] as int,
    label: payload['label'] as String,
    fields: (payload['fields'] as List).cast<Map<String, dynamic>>().map(
      LayoutField.fromJson,
    ),
    headings: readHeadings(settings['headings']),
    origin: TemplateOrigin.values.byName(
      settings['origin'] as String? ?? 'user',
    ),
    description: settings['description'] as String?,
    translations: readTranslations(settings['translations']),
    descriptionTranslations: readTranslations(
      settings['descriptionTranslations'],
    ),
  );
  encodeTemplateDefinition(recipe, maximumFields: maximumFields);
  return recipe;
}

String encodeSettings(Map<String, Object?> payload) =>
    jsonEncode(_ordered(payload));

Object? _ordered(Object? value, {bool sortKeys = true}) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList();
    if (sortKeys) keys.sort();
    return {
      for (final key in keys)
        key: _ordered(value[key], sortKeys: key != 'choices'),
    };
  }
  if (value is List) return [for (final item in value) _ordered(item)];
  return value;
}
