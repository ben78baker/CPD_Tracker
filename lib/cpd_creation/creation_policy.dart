import 'dart:convert';

import '../cpd_compatibility/cpd_layout_policy.dart';
import '../recording_engine/layout_draft.dart';
import '../recording_engine/models.dart';

enum ProfessionKind { standard, custom, template }

enum PurchaseState { pending, cancelled, verified }

class CreationAccess {
  CreationAccess({
    this.customFields = false,
    this.legacy = false,
    Iterable<String> templates = const [],
    Iterable<String> activeTrials = const [],
  }) : templates = Set.unmodifiable(templates),
       activeTrials = Set.unmodifiable(activeTrials);

  final bool customFields;
  final bool legacy;
  final Set<String> templates;
  final Set<String> activeTrials;
  bool get canCustomiseFields => customFields || legacy;

  bool hasTemplateAccess(String? id) =>
      templates.contains(id) || activeTrials.contains(id);

  bool allows(ProfessionKind kind, String? templateId) => switch (kind) {
    ProfessionKind.standard => true,
    ProfessionKind.custom => canCustomiseFields,
    ProfessionKind.template => hasTemplateAccess(templateId),
  };
}

class TemplateAccessException implements Exception {
  const TemplateAccessException();
}

class ReportSelection {
  ReportSelection({Iterable<String> excluded = const []})
    : excluded = Set.unmodifiable(excluded);

  final Set<String> excluded;

  ReportSelection remap(Map<String, String> ids) =>
      ReportSelection(excluded: excluded.map((id) => ids[id] ?? id));

  List<String> toJson() => excluded.toList()..sort();
  factory ReportSelection.fromJson(List<dynamic> raw) =>
      ReportSelection(excluded: raw.cast<String>());
}

class SchemeReportRules {
  SchemeReportRules({
    required this.version,
    required Iterable<String> requiredDefinitions,
  }) : requiredDefinitions = Set.unmodifiable(requiredDefinitions);

  final int version;
  final Set<String> requiredDefinitions;

  bool needs(LayoutField field) =>
      requiredDefinitions.contains(field.definition.id);

  ReportCompatibility assess(
    LayoutRevision supplied,
    LayoutDraft layout,
    ReportSelection report,
  ) {
    final active = {for (final field in layout.fields) field.id: field};
    final missing = <LayoutField>[];
    for (final field in supplied.fields.where(needs)) {
      final current = active[field.id];
      if (current == null ||
          report.excluded.contains(field.id) ||
          !_supports(current.definition, field.definition)) {
        missing.add(field);
      }
    }
    return ReportCompatibility(
      missing,
      report.excluded.isNotEmpty ||
          supplied.fields.any(
            (field) => !needs(field) && !active.containsKey(field.id),
          ),
    );
  }

  bool _supports(FieldDefinition current, FieldDefinition supplied) =>
      current.hasSameValueMeaning(supplied) &&
      supplied.choices.length == current.choices.length &&
      supplied.choices.entries.every(
        (choice) => current.choices[choice.key] == choice.value,
      );
}

class ReportCompatibility {
  ReportCompatibility(Iterable<LayoutField> missing, this.optionalChanges)
    : missing = List.unmodifiable(missing);

  final List<LayoutField> missing;
  final bool optionalChanges;
  bool get incomplete => missing.isNotEmpty;
}

void checkTemplateArrangement(
  LayoutRevision supplied,
  LayoutDraft draft,
  ReportSelection report,
  SchemeReportRules rules,
) {
  final originals = {for (final field in supplied.fields) field.id: field};
  final current = {for (final field in draft.fields) field.id: field};
  if (draft.includeExisting.isNotEmpty ||
      current.entries.any((entry) {
        final original = originals[entry.key];
        return original == null ||
            jsonEncode(original.toJson()) != jsonEncode(entry.value.toJson());
      }) ||
      originals.values.any(
        (field) => field.required && !current.containsKey(field.id),
      ) ||
      report.excluded.any(
        (id) => !originals.containsKey(id) || rules.needs(originals[id]!),
      )) {
    throw StateError(
      'Template ownership allows arrangement and optional report fields.',
    );
  }
  final suppliedHeadings = {
    for (final heading in supplied.headings) heading.id: heading.label,
  };
  if (draft.headings.length != supplied.headings.length ||
      draft.headings.any(
        (heading) => suppliedHeadings[heading.id] != heading.label,
      )) {
    throw StateError('Template ownership preserves supplied headings.');
  }
  checkCpdLayoutEdit(supplied.fields, draft.fields);
}
