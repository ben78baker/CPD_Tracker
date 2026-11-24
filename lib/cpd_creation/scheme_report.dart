import 'dart:typed_data';

import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;

import '../cpd_compatibility/report_locale.dart';
import '../l10n/app_localizations.dart';
import '../recording_engine/models.dart';
import '../recording_reports/activity_document.dart';
import 'scheme_period_store.dart';
import 'scheme_progress.dart';
import 'template_bundle.dart';

String formatSchemeDate(String day, AppLocalizations strings) =>
    ReportLocale(strings).date(DateTime.parse('${day}T00:00:00Z'));

String formatSchemePeriod(SchemePeriod period, AppLocalizations strings) =>
    '${formatSchemeDate(period.start, strings)} – ${formatSchemeDate(period.lastDay, strings)}';

String formatSchemeMinutes(int minutes, AppLocalizations strings) =>
    ReportLocale(strings).duration(minutes);

String schemeIssueLabel(ActivityIssue issue, AppLocalizations s) =>
    switch (issue) {
      ActivityIssue.unknownDate => s.p7IssueDate,
      ActivityIssue.missingValues => s.p7IssueMissing,
      ActivityIssue.invalidValues => s.p7IssueInvalid,
      ActivityIssue.unavailableEvidence => s.p7IssueEvidence,
      ActivityIssue.splitAcrossPeriod => s.p7IssueSplit,
    };

Future<Uint8List> buildSchemeReport({
  required ProfessionTemplateBundle bundle,
  required SchemeProgress progress,
  required Map<String, LayoutField> bindings,
  required Map<String, SchemeEvidence> evidence,
  required AppLocalizations strings,
  required String practitioner,
  ReportLocale? reportLocale,
  Uint8List? brandIcon,
  Set<String> excluded = const {},
  bool incompleteLayout = false,
  bool example = false,
  pw.Font? regular,
  pw.Font? bold,
  List<pw.Font> fallback = const [],
}) async => buildActivityDocument(
  await prepareSchemeReport(
    bundle: bundle,
    progress: progress,
    bindings: bindings,
    evidence: evidence,
    strings: strings,
    practitioner: practitioner,
    reportLocale: reportLocale,
    excluded: excluded,
    incompleteLayout: incompleteLayout,
    example: example,
  ),
  brandIcon: brandIcon,
  regular: regular,
  bold: bold,
  fallback: fallback,
);

List<String> schemeTraceabilityDetails(
  ProfessionTemplateBundle bundle,
  SchemePeriod period,
  AppLocalizations strings,
) => [
  '${strings.editorVersion} ${period.templateVersion}',
  '${strings.p7RuleRevision} ${period.ruleVersion}',
  '${strings.p7Reviewed} · ${formatSchemeDate(bundle.reviewed, strings)}',
];

Future<ActivityDocumentData> prepareSchemeReport({
  required ProfessionTemplateBundle bundle,
  required SchemeProgress progress,
  required Map<String, LayoutField> bindings,
  required Map<String, SchemeEvidence> evidence,
  required AppLocalizations strings,
  required String practitioner,
  ReportLocale? reportLocale,
  Set<String> excluded = const {},
  bool incompleteLayout = false,
  bool example = false,
}) async {
  await initializeDateFormatting();
  final display = reportLocale ?? ReportLocale(strings);
  final s = display.strings;
  final locale = display.tag;
  String date(String day) => display.date(DateTime.parse('${day}T00:00:00Z'));
  final foreignSource = s.localeName != bundle.sourceLanguage;
  var sourceLanguageUsed = false;
  String localised(
    String key,
    String fallback, {
    bool fallbackTranslated = false,
  }) {
    final text = bundle.translatedLabel(key, locale);
    if (text == null && !fallbackTranslated && foreignSource) {
      sourceLanguageUsed = true;
    }
    return text ?? fallback;
  }

  final titleField = bindings[bundle.inputs[ActivityInput.title]]!;
  final byInstance = {
    for (final entry in bindings.entries) entry.value.id: entry.key,
  };
  final appendix = <String, ({String number, DocumentReference reference})>{};
  String attachmentReference(String id) => appendix.putIfAbsent(id, () {
    final item = evidence[id];
    final number = 'E${display.integer(appendix.length + 1)}';
    final label = '$number · ${item?.name ?? id}';
    return (
      number: number,
      reference: (
        label: item?.available == true
            ? label
            : '$label · ${s.p7IssueEvidence}',
        url: item?.available == true ? item?.url : null,
      ),
    );
  }).number;

  String valueLabel(LayoutField field, Object value) {
    final def = field.definition;
    try {
      def.validate(value);
    } on ArgumentError {
      return '${value.toString()} · ${s.p7IssueInvalid}';
    }
    if (def.choices.isNotEmpty && foreignSource) {
      // Controlled labels are retained as authored for each historical version.
      sourceLanguageUsed = true;
    }
    return switch (def.kind) {
      FieldKind.attachments =>
        (value as List)
            .cast<String>()
            .toSet()
            .map(attachmentReference)
            .join(', '),
      FieldKind.duration => display.duration(value as int),
      FieldKind.date => date(value as String),
      FieldKind.integer => display.integer(value as int),
      FieldKind.decimal => display.decimal(value as String),
      FieldKind.multipleChoices => (def.displayValue(value) as List).join(', '),
      _ => def.displayValue(value).toString(),
    };
  }

  String fieldLabel(LayoutField field) {
    final label = field.localizedLabel(locale);
    final key = byInstance[field.id];
    final original = bindings[key]?.definition;
    if (field.labelOverride != null ||
        original == null ||
        field.definition.id != original.id ||
        field.definition.version != original.version) {
      return label;
    }
    return localised(
      key!,
      label,
      fallbackTranslated: localize(
        '',
        field.definition.translations,
        locale,
      ).isNotEmpty,
    );
  }

  final activities = <DocumentActivity>[
    for (final result in progress.activities)
      (
        title: switch (result.activity.values[titleField.id]) {
          final String title
              when title.trim().isNotEmpty &&
                  !excluded.contains(titleField.id) =>
            title,
          _ => s.noTitle,
        },
        status: result.issues
            .map((issue) => schemeIssueLabel(issue, s))
            .join(' · '),
        fields: [
          for (final field in result.activity.fields)
            if (!excluded.contains(field.id) &&
                field.id != titleField.id &&
                (!byInstance.containsKey(field.id) ||
                    bundle.reportFields.contains(byInstance[field.id])))
              if (result.activity.values[field.id] case final value?)
                (label: fieldLabel(field), value: valueLabel(field, value)),
        ],
      ),
  ];
  final period = progress.period;
  final title = localised(
    'report',
    bundle.recipe.localizedLabel(locale),
    fallbackTranslated: localize(
      '',
      bundle.recipe.translations,
      locale,
    ).isNotEmpty,
  );
  final periodLabel = localised('period', s.p7Period, fallbackTranslated: true);
  final scope = localised('scope', s.p7ReportScope, fallbackTranslated: true);
  final metricRows = [
    for (final metric in bundle.metrics)
      [
        localised(metric.id, metric.id),
        display.duration(metric.target),
        display.duration(progress.metrics[metric.id]!.recorded),
        display.duration(progress.metrics[metric.id]!.complete),
        display.duration(progress.metrics[metric.id]!.eligible),
      ],
  ];
  return ActivityDocumentData(
    title: title,
    appName: 'CPD Progress Tracker',
    attribution: s.p7aAttribution,
    documentTag: example ? s.p7Synthetic : s.p7Internal,
    branding: bundle.branding,
    summaryTitle: s.p7Summary,
    summaryColumns: [
      s.p7aReportMeasure,
      s.p7Target,
      s.p7Recorded,
      s.p7Complete,
      s.p7aEligible,
    ],
    summaryRows: metricRows,
    metadata: [
      if (practitioner.trim().isNotEmpty)
        '${s.p7Practitioner} · ${practitioner.trim()}',
      '$periodLabel · ${date(period.start)} - ${date(period.lastDay)}',
      if (bundle.showDeadline)
        period.deadline == null
            ? s.p7MissingDeadline
            : '${s.p7Deadline} · ${date(period.deadline!)}',
    ],
    summary: [
      if (progress.incomplete > 0)
        '${s.p7ReviewLog} · ${display.integer(progress.incomplete)}',
      if (incompleteLayout) s.p7LayoutWarning,
      scope,
      if (sourceLanguageUsed) s.reportTemplateLanguageFallback,
    ],
    activities: activities,
    evidenceTitle: s.p7EvidenceIndex,
    evidence: appendix.values.map((item) => item.reference).toList(),
    continued: s.cpdPdfContinuedTitle,
    pageOf: s.pageOf,
  );
}

Future<Uint8List> buildBundleExampleReport({
  required ProfessionTemplateBundle bundle,
  required SchemePeriod period,
  required AppLocalizations strings,
  ReportLocale? reportLocale,
  Uint8List? brandIcon,
  pw.Font? regular,
  pw.Font? bold,
  List<pw.Font> fallback = const [],
}) {
  final bindings = {for (final field in bundle.recipe.fields) field.id: field};
  final progress = calculateSchemeProgress(
    bundle: bundle,
    period: period,
    activities: bundle.examples.indexed.map(
      (item) => SchemeActivity(
        item.$1.toString(),
        bundle.recipe.fields,
        item.$2.values,
      ),
    ),
    adoptedFields: bindings,
    availableEvidence: bundle.sampleEvidence.keys.toSet(),
  );
  return buildSchemeReport(
    bundle: bundle,
    progress: progress,
    bindings: bindings,
    strings: strings,
    practitioner: (reportLocale?.strings ?? strings).p7Synthetic,
    reportLocale: reportLocale,
    brandIcon: brandIcon,
    example: true,
    evidence: {
      for (final item in bundle.sampleEvidence.entries)
        item.key: (name: item.value, available: true, url: null),
    },
    regular: regular,
    bold: bold,
    fallback: fallback,
  );
}
