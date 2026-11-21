import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_reports/activity_document_data.dart';

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

const hindiTitle = 'शिक्षा और व्यावसायिक प्रशिक्षण';
const hindiMixed = 'Pratique clinique · हिन्दी में चिकित्सा क्षेत्र · CPD 2026';
const hindiClosing =
    'समापन टिप्पणी · Prüfung abgeschlossen · प्रशिक्षण पूरा हुआ।';
const evidenceUri = 'https://example.com/resources/learning-log';
const evidenceLongUri = 'https://example.com/evidence/long-path/';
const stressClosing =
    'Final original text · Revisión terminada · Prüfung abgeschlossen.';
final stressNoBreak = List.generate(
  120,
  (i) => 'REF${i.toString().padLeft(3, '0')}',
).join();
final stressUrl =
    '$evidenceLongUri${List.generate(92, (i) => 'PATH${i.toString().padLeft(3, '0')}').join()}';

Future<ActivityDocumentData> preparedStressReport({
  required int activities,
  ReportLanguage language = ReportLanguage.englishUk,
  bool complexScript = false,
  ProfessionTemplateBundle? template,
}) async {
  final bundle = template ?? nursingBundle;
  final bindings = {for (final field in bundle.recipe.fields) field.id: field};
  final date = bundle.inputs[ActivityInput.date]!;
  final title = bundle.inputs[ActivityInput.title]!;
  final details = bundle.inputs[ActivityInput.details]!;
  final evidence = bundle.inputs[ActivityInput.evidence]!;
  final participation = bundle.inputs[ActivityInput.participatory]!;
  final minutes = bundle.inputs[ActivityInput.minutes]!;
  final first = bundle.examples.first;
  final retired = LayoutField(
    id: 'retired.note',
    definition: FieldDefinition(
      id: 'history.note',
      version: 1,
      label: 'Archived supervisor note',
      kind: FieldKind.text,
    ),
  );
  final history = [
    LayoutRevision(
      collectionId: 'test',
      version: 1,
      fields: [...bundle.recipe.fields, retired],
    ),
    LayoutRevision(
      collectionId: 'test',
      version: 2,
      fields: bundle.recipe.fields,
    ),
  ];
  final references = <String, SchemeEvidence>{
    'log': (
      name: 'Shared attendance log.pdf',
      available: true,
      url: evidenceUri,
    ),
    'same-name': (
      name: 'Shared attendance log.pdf',
      available: true,
      url: stressUrl,
    ),
    'missing': (name: 'Unavailable original.pdf', available: false, url: null),
    'unresolved': (
      name: 'Provider file.pdf',
      available: false,
      url: 'https://example.com/do-not-link',
    ),
  };
  final sample = List.generate(activities, (index) {
    final number = index.toString().padLeft(4, '0');
    final long = complexScript ? index < 2 : index.isEven && index < 6;
    final notes = complexScript
        ? [
            hindiMixed,
            if (long)
              ...List.generate(
                85,
                (i) =>
                    'अवलोकन ${i + 1} · व्यावसायिक प्रशिक्षण में संयुक्त अक्षर, चिकित्सा और कौशल का अभ्यास किया।',
              ),
            hindiClosing,
          ].join('\n')
        : [
            'Record integrity marker $number. Original note: Formation en français et revisión en español.',
            if (long)
              ...List.generate(
                68,
                (i) =>
                    'Observation $number-${i + 1}. Reviewed the learning objectives and applied the findings.',
              ),
            if (index == 0) ...[stressNoBreak, stressUrl, stressClosing],
          ].join('\n');
    return SchemeActivity(
      'record-$number',
      resolveFields(index == 0 ? 1 : 2, history),
      {
          ...first.values,
          title: complexScript
              ? index == 0
                    ? hindiTitle
                    : 'चिकित्सा अभ्यास · Mixed-language session $number'
              : 'Activity $number - applying learning',
          date: complexScript
              ? '2026-10-1${index + 1}'
              : schemeDay(DateTime.utc(2024, 1, 1 + index * 3)),
          details: notes,
          evidence: index == 0
              ? ['log', 'log', 'same-name', 'missing', 'unresolved']
              : ['log'],
          minutes: index % 4 == 0 ? 90 : 65,
          participation: index % 4 == 0 ? 45 : 30,
          if (index == 0) retired.id: 'Preserved historical supervisor value',
        }
        ..remove('nmc.practice') // absent optional value
        ..['nmc.standards'] = 'EXCLUDED TEST VALUE',
    );
  });
  final reportLocale = await ReportLocale.resolve(
    language,
    AppLocalizationsEn(),
  );
  return prepareSchemeReport(
    bundle: bundle,
    progress: calculateSchemeProgress(
      bundle: bundle,
      period: rehearsalPeriod,
      activities: sample,
      adoptedFields: bindings,
      availableEvidence: references.entries
          .where((entry) => entry.value.available)
          .map((entry) => entry.key)
          .toSet(),
    ),
    bindings: bindings,
    evidence: references,
    strings: AppLocalizationsEn(),
    reportLocale: reportLocale,
    practitioner: complexScript
        ? 'डॉ. आशा शर्मा · Asha Sharma'
        : 'Élodie Silva',
    excluded: {'nmc.standards'},
    example: true,
  );
}
