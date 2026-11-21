import 'dart:convert';

import '../cpd_compatibility/cpd_layout_policy.dart';
import '../recording_engine/models.dart';
import '../recording_engine/template_review.dart';
import '../recording_reports/activity_document_data.dart';

enum ActivityInput {
  date(FieldKind.date),
  title(FieldKind.text),
  details(FieldKind.text),
  minutes(FieldKind.duration),
  participatory(FieldKind.duration),
  evidence(FieldKind.attachments),
  method(FieldKind.choice),
  code(FieldKind.multipleChoices),
  firstDay(FieldKind.date);

  const ActivityInput(this.kind);
  final FieldKind kind;
}

enum PeriodKind { custom, fixed, rolling }

class SchemeMetric {
  const SchemeMetric(
    this.id,
    this.input,
    this.target, {
    this.methods = const [],
  });

  final String id;
  final ActivityInput input;
  final int target;
  final List<String> methods;

  Map<String, Object?> toJson() => {
    'id': id,
    'input': input.name,
    'targetMinutes': target,
    'methods': methods,
  };

  factory SchemeMetric.fromJson(Map<String, dynamic> json) => SchemeMetric(
    json['id'] as String,
    ActivityInput.values.byName(json['input'] as String),
    json['targetMinutes'] as int,
    methods: List.unmodifiable((json['methods'] as List).cast<String>()),
  );
}

class BundleExample {
  BundleExample(this.title, Map<String, Object> values)
    : values = Map.unmodifiable(
        values.map(
          (key, value) => MapEntry(
            key,
            value is List ? List<Object?>.unmodifiable(value) : value,
          ),
        ),
      );
  final String title;
  final Map<String, Object> values;

  Map<String, Object?> toJson() => {'title': title, 'values': values};
}

/// CPD catalogue envelope. The embedded recipe has no commercial or scheme logic.
/// Delivery must keep prior envelopes available for their pinned periods.
class ProfessionTemplateBundle {
  ProfessionTemplateBundle.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['format'] != 1 || json['minimumReader'] != reader) {
      throw const FormatException('Unsupported CPD bundle compatibility.');
    }
    recipe = decodeTemplateDefinition(
      jsonEncode(json['recipe']),
      maximumFields: cpdActiveFieldLimit,
    );
    scheme = json['scheme'] as String;
    profession = json['profession'] as String;
    country = json['country'] as String;
    body = json['body'] as String;
    sourceLanguage = json['sourceLanguage'] as String? ?? 'en';
    reviewed = json['reviewed'] as String;
    product = json['product'] as String;
    sources = List.unmodifiable((json['sources'] as List).cast<String>());
    final rules = json['rules'] as Map<String, dynamic>;
    calculator = rules['calculator'] as String;
    ruleVersion = rules['version'] as int;
    inputs = Map.unmodifiable(
      (rules['inputs'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(ActivityInput.values.byName(key), value as String),
      ),
    );
    requiredInputs = Set.unmodifiable(
      (rules['required'] as List).cast<String>().map(
        ActivityInput.values.byName,
      ),
    );
    periods = Set.unmodifiable(
      (rules['periods'] as List).cast<String>().map(PeriodKind.values.byName),
    );
    cycleMonths = rules['cycleMonths'] as int;
    metrics = List.unmodifiable(
      (rules['metrics'] as List).cast<Map<String, dynamic>>().map(
        SchemeMetric.fromJson,
      ),
    );
    final tile = json['tile'] as Map<String, dynamic>;
    tileMetrics = List.unmodifiable((tile['metrics'] as List).cast<String>());
    showDeadline = tile['deadline'] as bool;
    final report = json['report'] as Map<String, dynamic>;
    if (report['kind'] != 'activity_log_v1') {
      throw const FormatException('Unsupported report renderer.');
    }
    reportVersion = report['version'] as int;
    final brand = report['branding'] as String?;
    if (brand != null &&
        !ReportBranding.values.any((mode) => mode.name == brand)) {
      throw const FormatException('Unsupported report branding.');
    }
    branding = brand == null
        ? ReportBranding.subtle
        : ReportBranding.values.byName(brand);
    reportFields = List.unmodifiable((report['fields'] as List).cast<String>());
    final preview = json['preview'] as Map<String, dynamic>;
    sampleEvidence = Map.unmodifiable(
      (preview['evidence'] as Map).cast<String, String>(),
    );
    examples = List.unmodifiable(
      (preview['examples'] as List).cast<Map<String, dynamic>>().map(
        (example) => BundleExample(
          example['title'] as String,
          (example['values'] as Map).cast<String, Object>(),
        ),
      ),
    );
    labels = Map.unmodifiable(
      (json['labels'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          Map<String, String>.unmodifiable(readTranslations(value)),
        ),
      ),
    );
    if (!const {'en', 'de', 'es', 'fr', 'hi', 'pt'}.contains(sourceLanguage)) {
      throw const FormatException('Unsupported template source language.');
    }
    _validate();
  }

  static const reader = 1;
  late final TemplateVersion recipe;
  late final String scheme,
      profession,
      country,
      body,
      reviewed,
      product,
      calculator;
  late final int ruleVersion, cycleMonths, reportVersion;
  late final List<String> sources, tileMetrics, reportFields;
  late final Map<ActivityInput, String> inputs;
  late final Set<ActivityInput> requiredInputs;
  late final Set<PeriodKind> periods;
  late final List<SchemeMetric> metrics;
  late final bool showDeadline;
  late final ReportBranding branding;
  late final String sourceLanguage;
  late final Map<String, String> sampleEvidence;
  late final List<BundleExample> examples;
  late final Map<String, Map<String, String>> labels;

  LayoutField field(String key) =>
      recipe.fields.singleWhere((field) => field.id == key);
  String label(String key, String fallback, String locale) =>
      localize(fallback, labels[key] ?? const {}, locale);

  String? translatedLabel(String key, String locale) {
    final translations = labels[key] ?? const <String, String>{};
    final display = localize('', translations, locale);
    return display.isEmpty ? null : display;
  }

  Set<String> get protectedKeys => {
    for (final input in requiredInputs) inputs[input]!,
  };

  void _validate() {
    final fields = {for (final field in recipe.fields) field.id: field};
    void check(bool valid, String message) {
      if (!valid) throw FormatException(message);
    }

    check(
      recipe.origin == TemplateOrigin.bundled &&
          [
            scheme,
            profession,
            country,
            body,
            product,
          ].every((value) => value.trim().isNotEmpty) &&
          isCalendarDay(reviewed) &&
          sources.isNotEmpty &&
          sources.every(
            (source) => switch (Uri.tryParse(source)) {
              Uri(scheme: 'https', hasAuthority: true) => true,
              _ => false,
            },
          ),
      'Invalid bundle identity or regulatory references.',
    );
    check(
      calculator == 'log_minutes_v1' &&
          ruleVersion >= 1 &&
          reportVersion == 1 &&
          periods.isNotEmpty &&
          cycleMonths >= 1 &&
          cycleMonths <= 120,
      'Unsupported report, calendar or calculator version.',
    );
    const mandatory = {
      ActivityInput.date,
      ActivityInput.minutes,
      ActivityInput.title,
    };
    check(
      inputs.values.toSet().length == inputs.length &&
          requiredInputs.containsAll(mandatory) &&
          inputs.keys.toSet().containsAll(requiredInputs) &&
          inputs.entries.every(
            (binding) =>
                fields[binding.value]?.definition.kind == binding.key.kind,
          ),
      'Invalid activity field binding.',
    );
    final metricIds = metrics.map((metric) => metric.id).toSet();
    check(
      metrics.isNotEmpty &&
          metricIds.length == metrics.length &&
          metrics.every(
            (metric) =>
                metric.id.trim().isNotEmpty &&
                metric.target > 0 &&
                {
                  ActivityInput.minutes,
                  ActivityInput.participatory,
                }.contains(metric.input) &&
                requiredInputs.contains(metric.input) &&
                metric.methods.every(
                  (method) =>
                      inputs.containsKey(ActivityInput.method) &&
                      field(
                        inputs[ActivityInput.method]!,
                      ).definition.choices.containsKey(method),
                ),
          ),
      'Invalid target or qualifying category.',
    );
    final totalTargets = metrics
        .where(
          (metric) =>
              metric.input == ActivityInput.minutes && metric.methods.isEmpty,
        )
        .map((metric) => metric.target);
    check(
      metrics
          .where(
            (metric) =>
                metric.input == ActivityInput.participatory &&
                metric.methods.isEmpty,
          )
          .every(
            (metric) =>
                totalTargets.isEmpty ||
                totalTargets.any((target) => target >= metric.target),
          ),
      'Participatory requirement exceeds the applicable total.',
    );
    check(
      tileMetrics.isNotEmpty &&
          tileMetrics.toSet().length == tileMetrics.length &&
          metricIds.containsAll(tileMetrics),
      'Unknown or duplicate tile metric.',
    );
    check(
      reportFields.toSet().length == reportFields.length &&
          fields.keys.toSet().containsAll(reportFields) &&
          reportFields.toSet().containsAll(protectedKeys),
      'Incompatible report field selection.',
    );
    check(
      labels.keys.every(
            (key) =>
                fields.containsKey(key) ||
                metricIds.contains(key) ||
                key == 'description' ||
                key == 'report' ||
                key == 'periodHint' ||
                key == 'period' ||
                key == 'scope',
          ) &&
          labels.values.every(
            (translations) =>
                translations.values.every((text) => text.trim().isNotEmpty),
          ),
      'Unknown or blank localised label.',
    );
    check(
      examples.isNotEmpty &&
          sampleEvidence.entries.every(
            (item) =>
                item.key.startsWith('preview.') && item.value.trim().isNotEmpty,
          ),
      'Missing example or unsafe preview evidence reference.',
    );
    for (final example in examples) {
      check(
        example.title.trim().isNotEmpty &&
            fields.keys.toSet().containsAll(example.values.keys) &&
            example.values.keys.toSet().containsAll(protectedKeys) &&
            fields.values
                .where((field) => field.required)
                .every((field) => example.values.containsKey(field.id)),
        'Incomplete preview example.',
      );
      for (final value in example.values.entries) {
        final definition = fields[value.key]!.definition;
        definition.validate(value.value);
        check(
          value.value is! String || (value.value as String).trim().isNotEmpty,
          'Blank preview value.',
        );
        if (definition.kind == FieldKind.attachments) {
          check(
            (value.value as List).every(sampleEvidence.containsKey),
            'Unknown preview evidence.',
          );
        }
      }
      final values = example.values;
      final part = values[inputs[ActivityInput.participatory]] as int?;
      final start = values[inputs[ActivityInput.firstDay]] as String?;
      check(
        (part == null ||
                part <= (values[inputs[ActivityInput.minutes]] as int)) &&
            (start == null ||
                start.compareTo(values[inputs[ActivityInput.date]] as String) <=
                    0),
        'Inconsistent preview duration or dates.',
      );
    }
  }

  String encode() => encodeSettings({
    'format': 1,
    'minimumReader': reader,
    'recipe': jsonDecode(
      encodeTemplateDefinition(recipe, maximumFields: cpdActiveFieldLimit),
    ),
    'scheme': scheme,
    'profession': profession,
    'country': country,
    'body': body,
    'sourceLanguage': sourceLanguage,
    'reviewed': reviewed,
    'product': product,
    'sources': sources,
    'rules': regulatoryConfiguration,
    'tile': {'metrics': tileMetrics, 'deadline': showDeadline},
    'report': {
      'kind': 'activity_log_v1',
      'version': reportVersion,
      'branding': branding.name,
      'fields': reportFields,
    },
    'preview': {
      'evidence': sampleEvidence,
      'examples': [for (final example in examples) example.toJson()],
    },
    'labels': labels,
  });

  Map<String, Object?> get regulatoryConfiguration => {
    'calculator': calculator,
    'version': ruleVersion,
    'inputs': {for (final entry in inputs.entries) entry.key.name: entry.value},
    'required': requiredInputs.map((input) => input.name).toList()..sort(),
    'periods': periods.map((period) => period.name).toList()..sort(),
    'cycleMonths': cycleMonths,
    'metrics': [for (final metric in metrics) metric.toJson()],
  };

  /// Validate an offered update before passing its recipe to TemplateReview.
  bool changesRegulatoryRules(ProfessionTemplateBundle offered) {
    if (recipe.id != offered.recipe.id ||
        product != offered.product ||
        scheme != offered.scheme ||
        recipe.version >= offered.recipe.version) {
      throw ArgumentError(
        'Update must advance the same template and store product.',
      );
    }
    Map<String, Object?> regulations(ProfessionTemplateBundle bundle) => {
      ...bundle.regulatoryConfiguration,
      'definitions': {
        for (final entry in bundle.inputs.entries)
          entry.key.name: {
            'id': bundle.field(entry.value).definition.id,
            'kind': bundle.field(entry.value).definition.kind.name,
            'choices': bundle.field(entry.value).definition.choices,
          },
      },
    };
    final changed =
        encodeSettings(regulations(this)) !=
        encodeSettings(regulations(offered));
    if (changed && ruleVersion >= offered.ruleVersion) {
      throw ArgumentError('Regulatory changes require a new rule version.');
    }
    return changed;
  }
}
