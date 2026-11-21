import '../recording_engine/models.dart';
import 'template_bundle.dart';

DateTime _day(String value) {
  if (!isCalendarDay(value)) {
    throw FormatException('Invalid calendar day.', value);
  }
  return DateTime.parse('${value}T00:00:00Z');
}

String schemeDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime _addMonths(DateTime day, int months) {
  final first = DateTime.utc(day.year, day.month + months);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(first.year, first.month, day.day > last ? last : day.day);
}

/// A persisted calendar window. Rolling windows are evaluated as of an explicit
/// day; saving a window freezes its bounds for historical reporting.
class SchemePeriod {
  SchemePeriod({
    required this.id,
    required this.kind,
    required this.templateId,
    required this.templateVersion,
    required this.ruleVersion,
    required this.start,
    required this.end,
    this.deadline,
  }) {
    if (id.trim().isEmpty ||
        templateId.trim().isEmpty ||
        templateVersion < 1 ||
        ruleVersion < 1 ||
        !_day(start).isBefore(_day(end))) {
      throw ArgumentError(
        'The period needs a valid identity and ordered dates.',
      );
    }
    if (deadline != null) _day(deadline!);
  }

  factory SchemePeriod.create(
    ProfessionTemplateBundle bundle, {
    required String id,
    required PeriodKind kind,
    required String anchor,
    String? end,
    String? deadline,
  }) {
    if (!bundle.periods.contains(kind) ||
        (kind == PeriodKind.custom) != (end != null)) {
      throw ArgumentError('Unsupported period or date combination.');
    }
    final day = _day(anchor);
    return SchemePeriod(
      id: id,
      kind: kind,
      templateId: bundle.recipe.id,
      templateVersion: bundle.recipe.version,
      ruleVersion: bundle.ruleVersion,
      start: kind == PeriodKind.rolling
          ? schemeDay(
              _addMonths(day.add(const Duration(days: 1)), -bundle.cycleMonths),
            )
          : anchor,
      end: switch (kind) {
        PeriodKind.custom => end!,
        PeriodKind.fixed => schemeDay(_addMonths(day, bundle.cycleMonths)),
        PeriodKind.rolling => schemeDay(day.add(const Duration(days: 1))),
      },
      deadline: deadline,
    );
  }

  final String id, templateId, start, end;
  final String? deadline;
  final PeriodKind kind;
  final int templateVersion, ruleVersion;

  String get lastDay => schemeDay(_day(end).subtract(const Duration(days: 1)));

  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) < 0;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'templateId': templateId,
    'template': templateVersion,
    'rules': ruleVersion,
    'start': start,
    'endExclusive': end,
    'deadline': deadline,
  };

  factory SchemePeriod.fromJson(Map<String, dynamic> json) => SchemePeriod(
    id: json['id'] as String,
    kind: PeriodKind.values.byName(json['kind'] as String),
    templateId: json['templateId'] as String,
    templateVersion: json['template'] as int,
    ruleVersion: json['rules'] as int,
    start: json['start'] as String,
    end: json['endExclusive'] as String,
    deadline: json['deadline'] as String?,
  );
}

enum ActivityIssue {
  unknownDate,
  missingValues,
  invalidValues,
  unavailableEvidence,
  splitAcrossPeriod,
}

class SchemeActivity {
  const SchemeActivity(this.id, this.fields, this.values);
  final String id;
  final List<LayoutField> fields;
  final Map<String, Object> values;
}

typedef ActivityResult = ({
  SchemeActivity activity,
  String? day,
  Set<ActivityIssue> issues,
});
typedef MetricProgress = ({int recorded, int complete, int eligible});

class SchemeProgress {
  const SchemeProgress._(this.period, this.metrics, this.activities);

  final SchemePeriod period;
  final Map<String, MetricProgress> metrics;
  final List<ActivityResult> activities;

  int get incomplete =>
      activities.where((item) => item.issues.isNotEmpty).length;
  int get undated => activities.where((item) => item.day == null).length;
}

/// Bind recipe-local fields to this adoption, once. A later field with the
/// same label or definition ID cannot inherit the original statutory role.
Map<String, LayoutField> adoptedRecipeFields(
  ProfessionTemplateBundle bundle,
  LayoutRevision adoption,
) {
  final recipe = bundle.recipe;
  if (adoption.templateId != recipe.id ||
      adoption.templateVersion != recipe.version ||
      recipe.fields.length != adoption.fields.length) {
    throw StateError('No matching original layout for the pinned template.');
  }
  return {
    for (final (index, field) in recipe.fields.indexed)
      field.id: _checkAdoptionField(field, adoption.fields[index]),
  };
}

LayoutField _checkAdoptionField(LayoutField recipe, LayoutField instance) {
  if (!_sameMeaning(recipe.definition, instance.definition)) {
    throw StateError('The adoption has an inconsistent field binding.');
  }
  return instance;
}

bool _sameMeaning(FieldDefinition baseline, FieldDefinition historical) =>
    baseline.hasSameValueMeaning(historical) &&
    baseline.choices.length == historical.choices.length &&
    baseline.choices.entries.every(
      (choice) => historical.choices[choice.key] == choice.value,
    );

SchemeProgress calculateSchemeProgress({
  required ProfessionTemplateBundle bundle,
  required SchemePeriod period,
  required Iterable<SchemeActivity> activities,
  required Map<String, LayoutField> adoptedFields,
  required Set<String> availableEvidence,
}) {
  if (period.templateId != bundle.recipe.id ||
      period.templateVersion != bundle.recipe.version ||
      period.ruleVersion != bundle.ruleVersion ||
      !bundle.periods.contains(period.kind)) {
    throw StateError(
      'Reporting needs its original template and rule revision.',
    );
  }
  final totals = {
    for (final metric in bundle.metrics)
      metric.id: (recorded: 0, complete: 0, eligible: 0),
  };
  final results = <ActivityResult>[];
  final ids = <String>{};
  for (final entry in activities) {
    if (!ids.add(entry.id)) throw StateError('Duplicate activity identity.');
    final fields = {for (final field in entry.fields) field.id: field};
    final values = <ActivityInput, Object>{};
    final issues = <ActivityIssue>{};
    for (final input in bundle.inputs.entries) {
      final original = adoptedFields[input.value]!;
      final field = fields[original.id];
      final value = entry.values[original.id];
      if (value == null || value is String && value.trim().isEmpty) {
        if (bundle.requiredInputs.contains(input.key)) {
          issues.add(ActivityIssue.missingValues);
        }
        continue;
      }
      if (field == null ||
          !_sameMeaning(original.definition, field.definition)) {
        issues.add(ActivityIssue.invalidValues);
        continue;
      }
      try {
        original.definition.validate(value);
        values[input.key] = value;
      } on ArgumentError {
        issues.add(ActivityIssue.invalidValues);
      }
    }
    final date = values[ActivityInput.date] as String?;
    if (date == null) {
      results.add((
        activity: entry,
        day: null,
        issues: Set.unmodifiable({ActivityIssue.unknownDate, ...issues}),
      ));
      continue;
    }
    if (!period.contains(date)) continue;
    final start = values[ActivityInput.firstDay] as String?;
    if (start != null) {
      if (start.compareTo(date) > 0) {
        issues.add(ActivityIssue.invalidValues);
      } else if (!period.contains(start)) {
        // Keep the logged duration visible. Never apportion undocumented hours.
        issues.add(ActivityIssue.splitAcrossPeriod);
      }
    }
    final evidence = values[ActivityInput.evidence] as List?;
    if (evidence != null && !evidence.every(availableEvidence.contains)) {
      issues.add(ActivityIssue.unavailableEvidence);
    }
    final total = values[ActivityInput.minutes] as int?;
    final part = values[ActivityInput.participatory] as int?;
    if (part != null && (total == null || part > total)) {
      values.remove(ActivityInput.participatory);
      issues.add(ActivityIssue.invalidValues);
    }
    results.add((activity: entry, day: date, issues: Set.unmodifiable(issues)));
    for (final metric in bundle.metrics) {
      final minutes = values[metric.input] as int? ?? 0;
      final previous = totals[metric.id]!;
      final complete = issues.isEmpty;
      final eligible =
          complete &&
          (metric.methods.isEmpty ||
              metric.methods.contains(values[ActivityInput.method]));
      totals[metric.id] = (
        recorded: previous.recorded + minutes,
        complete: previous.complete + (complete ? minutes : 0),
        eligible: previous.eligible + (eligible ? minutes : 0),
      );
    }
  }
  results.sort((a, b) {
    final date = (b.day ?? '').compareTo(a.day ?? '');
    return date != 0 ? date : a.activity.id.compareTo(b.activity.id);
  });
  return SchemeProgress._(
    period,
    Map.unmodifiable(totals),
    List.unmodifiable(results),
  );
}
