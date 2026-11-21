import 'dart:typed_data';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_localizations.dart';
import '../recording_engine/models.dart';
import '../recording_reports/activity_document.dart';
import 'scheme_period_store.dart';
import 'scheme_progress.dart';
import 'template_bundle.dart';

String formatSchemeDate(String day, AppLocalizations strings) =>
    DateFormat.yMMMd(
      strings.localeName,
    ).format(DateTime.parse('${day}T00:00:00Z'));

String formatSchemePeriod(SchemePeriod period, AppLocalizations strings) =>
    '${formatSchemeDate(period.start, strings)} – ${formatSchemeDate(period.lastDay, strings)}';

String formatSchemeMinutes(int minutes, AppLocalizations strings) {
  if (minutes < 60) return strings.minutesPlural(minutes);
  final hours = strings.hoursPlural(minutes ~/ 60);
  return minutes % 60 == 0
      ? hours
      : '$hours ${strings.minutesPlural(minutes % 60)}';
}

String _issue(ActivityIssue issue, AppLocalizations s) => switch (issue) {
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
  Set<String> excluded = const {},
  bool incompleteLayout = false,
  bool example = false,
  pw.Font? regular,
  pw.Font? bold,
  List<pw.Font> fallback = const [],
}) async {
  final s = strings;
  await initializeDateFormatting(s.localeName);
  final locale = s.localeName;
  final titleField = bindings[bundle.inputs[ActivityInput.title]]!;
  final byInstance = {
    for (final entry in bindings.entries) entry.value.id: entry.key,
  };
  final appendix = <String, DocumentReference>{};
  String attachmentReference(String id) {
    final number = appendix.putIfAbsent(id, () {
      final item = evidence[id];
      final label = 'E${appendix.length + 1} · ${item?.name ?? id}';
      return (
        label: item?.available == true
            ? label
            : '$label · ${s.p7IssueEvidence}',
        url: item?.url,
      );
    });
    return number.label.split(' · ').first;
  }

  String valueLabel(LayoutField field, Object value) {
    final def = field.definition;
    try {
      def.validate(value);
    } on ArgumentError {
      return '${value.toString()} · ${s.p7IssueInvalid}';
    }
    return switch (def.kind) {
      FieldKind.attachments =>
        (value as List).cast<String>().map(attachmentReference).join(', '),
      FieldKind.duration => formatSchemeMinutes(value as int, s),
      FieldKind.date => formatSchemeDate(value as String, s),
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
    return bundle.label(key!, label, locale);
  }

  final activities = <DocumentActivity>[
    for (final (index, result) in progress.activities.indexed)
      (
        title: switch (result.activity.values[titleField.id]) {
          final String title
              when title.trim().isNotEmpty &&
                  !excluded.contains(titleField.id) =>
            title,
          _ => '${s.editorExample} ${index + 1}',
        },
        status: result.issues.map((issue) => _issue(issue, s)).join(' • '),
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
  return buildActivityDocument(
    title: bundle.label('report', bundle.recipe.localizedLabel(locale), locale),
    footer: '${s.appTitle} · ${example ? s.p7Synthetic : s.p7Internal}',
    summaryTitle: s.p7Summary,
    metadata: [
      if (practitioner.trim().isNotEmpty)
        '${s.p7Practitioner} · ${practitioner.trim()}',
      '${s.p7Period} · ${formatSchemePeriod(period, s).replaceAll(' – ', ' - ')}',
      if (bundle.showDeadline)
        period.deadline == null
            ? s.p7MissingDeadline
            : '${s.p7Deadline} · ${formatSchemeDate(period.deadline!, s)}',
    ],
    summary: [
      for (final metric in bundle.metrics)
        '${bundle.label(metric.id, metric.id, locale)} · ${s.p7Target} ${formatSchemeMinutes(metric.target, s)}\n'
            '${s.p7Recorded} ${formatSchemeMinutes(progress.metrics[metric.id]!.recorded, s)}  |  '
            '${s.p7Complete} ${formatSchemeMinutes(progress.metrics[metric.id]!.complete, s)}  |  '
            '${s.p7Eligible} ${formatSchemeMinutes(progress.metrics[metric.id]!.eligible, s)}',
      if (progress.incomplete > 0) '${s.p7ReviewLog} · ${progress.incomplete}',
      if (incompleteLayout) s.p7LayoutWarning,
      bundle.label('scope', s.p7ReportScope, locale),
    ],
    activities: activities,
    evidenceTitle: s.p7EvidenceIndex,
    evidence: appendix.values.toList(),
    versionNote:
        '${s.editorVersion} ${bundle.recipe.version} · ${s.p7RuleRevision} ${bundle.ruleVersion} · '
        '${s.p7Reviewed} ${formatSchemeDate(bundle.reviewed, s)}',
    regular: regular,
    bold: bold,
    fallback: fallback,
  );
}

Future<Uint8List> buildBundleExampleReport({
  required ProfessionTemplateBundle bundle,
  required SchemePeriod period,
  required AppLocalizations strings,
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
    practitioner: strings.p7Synthetic,
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
