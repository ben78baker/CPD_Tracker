import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../cpd_migration/legacy_migration.dart' show cpdStandardFields;
import '../recording_editor/template_preview.dart' show TemplatePreviewExample;
import '../recording_engine/models.dart';
import 'creation_policy.dart';

const nursingPilotId = 'uk.nmc.activity-log';
final nursingReviewDate = DateTime(2026, 11, 21);

LayoutField _field(
  String id,
  String name,
  FieldKind type, {
  bool required = false,
  bool multiline = false,
  Map<String, String> choices = const {},
  String? help,
}) => LayoutField(
  id: id,
  required: required,
  helpText: help,
  definition: FieldDefinition(
    id: id,
    version: 1,
    label: name,
    kind: type,
    multiline: multiline,
    choices: choices,
  ),
);

final nursingPilot = TemplateVersion(
  id: nursingPilotId,
  version: 1,
  origin: TemplateOrigin.bundled,
  label: 'UK nursing and midwifery activity log',
  description: 'Record learning for an NMC revalidation activity log.',
  translations: const {
    'de': 'Fortbildungsnachweis für Pflege und Geburtshilfe',
    'es': 'Registro de formación de enfermería y partería',
    'fr': 'Journal de formation infirmière et sage-femme',
    'hi': 'नर्सिंग और दाई सेवा का प्रशिक्षण रिकॉर्ड',
    'pt': 'Registo de formação em enfermagem e obstetrícia',
  },
  fields: [
    ...cpdStandardFields(nursingPilotId),
    _field(
      'nmc.method',
      'Learning method',
      FieldKind.choice,
      required: true,
      choices: const {
        'workshop': 'Workshop or facilitated session',
        'study': 'Independent study',
        'online': 'Online learning',
        'peer': 'Peer learning',
        'other': 'Other learning',
      },
    ),
    _field(
      'nmc.start',
      'First day if the activity spans dates',
      FieldKind.date,
    ),
    _field(
      'nmc.participatory',
      'Participatory minutes',
      FieldKind.duration,
      required: true,
      help:
          'Include only learning that involved interaction with others. Enter 0 if none.',
    ),
    _field(
      'nmc.code',
      'Relevant part or parts of the Code',
      FieldKind.multipleChoices,
      required: true,
      choices: const {
        'people': 'Prioritise people',
        'effective': 'Practise effectively',
        'safety': 'Preserve safety',
        'trust': 'Promote professionalism and trust',
      },
    ),
    _field(
      'nmc.practice',
      'Learning applied to practice',
      FieldKind.text,
      multiline: true,
      help:
          'Summarise what changed in your practice. Keep this note free of identifiable information.',
    ),
    _field(
      'nmc.standards',
      'Relevant standards of proficiency',
      FieldKind.text,
    ),
  ],
);

final nursingReportRules = SchemeReportRules(
  version: 1,
  requiredDefinitions: const [
    'cpd.activityDate',
    'cpd.details',
    'cpd.creditedDuration',
    'cpd.evidence',
    'nmc.method',
    'nmc.participatory',
    'nmc.code',
  ],
);

List<TemplatePreviewExample> nursingExamples(TemplateVersion recipe) {
  final ids = {
    for (final field in recipe.fields) field.definition.id: field.id,
  };
  TemplatePreviewExample entry(String label, Map<String, Object> data) =>
      TemplatePreviewExample(label, {
        for (final item in data.entries) ids[item.key]!: item.value,
      });
  return [
    entry('Clinical handover workshop', {
      'cpd.activityDate': '2026-10-14',
      'cpd.title': 'Clinical handover workshop',
      'cpd.details':
          'Practised a structured handover and escalation with colleagues to improve continuity of care.',
      'cpd.creditedDuration': 120,
      'nmc.participatory': 90,
      'nmc.method': 'workshop',
      'nmc.code': ['effective', 'safety'],
      'cpd.evidence': ['preview.sample'],
      'nmc.practice':
          'Used the handover checklist during the next simulated shift.',
      'nmc.standards': 'Communication and coordination of care',
    }),
    entry('Infection prevention guidance review', {
      'cpd.activityDate': '2026-09-29',
      'cpd.title': 'Infection prevention guidance review',
      'cpd.details':
          'Reviewed local guidance and considered how to improve equipment cleaning on the ward.',
      'cpd.creditedDuration': 45,
      'nmc.participatory': 0,
      'nmc.method': 'study',
      'nmc.code': ['safety'],
      'cpd.evidence': ['preview.sample'],
      'nmc.practice': 'Updated the reminder at the equipment station.',
    }),
    entry('Peer learning on medication reconciliation', {
      'cpd.activityDate': '2026-08-20',
      'cpd.title': 'Peer learning on medication reconciliation',
      'cpd.details':
          'Compared reconciliation scenarios with the pharmacy team to identify handoff gaps.',
      'cpd.creditedDuration': 75,
      'nmc.participatory': 75,
      'nmc.method': 'peer',
      'nmc.code': ['people', 'effective'],
      'cpd.evidence': ['preview.sample'],
      'nmc.practice':
          'Agreed a consistent question for checking discrepant medicines.',
    }),
  ];
}

class PilotReportEntry {
  PilotReportEntry(this.fields, this.values);
  final List<LayoutField> fields;
  final Map<String, Object> values;
}

Future<Uint8List> buildNursingActivityReport({
  required Iterable<PilotReportEntry> entries,
  required ReportSelection selection,
  required bool incompleteLayout,
  required int recipeVersion,
  required SchemeReportRules rules,
  required Map<String, String> requiredBindings,
  Map<String, String> evidenceNames = const {
    'preview.sample': 'Synthetic evidence reference',
  },
  bool example = false,
}) async {
  final document = pw.Document();
  final records = entries.toList();
  int total = 0;
  int participatory = 0;
  int incomplete = 0;
  final cards = <pw.Widget>[];
  for (final (index, entry) in records.indexed) {
    final included = entry.fields.where(
      (field) => !selection.excluded.contains(field.id),
    );
    final byDefinition = {
      for (final field in included) field.definition.id: entry.values[field.id],
    };
    final minutes = byDefinition['cpd.creditedDuration'];
    final interactive = byDefinition['nmc.participatory'];
    final missing = rules.requiredDefinitions.any((id) {
      final value = byDefinition[id];
      return value == null ||
          value is String && value.trim().isEmpty ||
          value is List &&
              (value.isEmpty ||
                  id == 'cpd.evidence' &&
                      !value.every(evidenceNames.containsKey));
    });
    if (missing ||
        minutes is! int ||
        interactive is! int ||
        interactive > minutes) {
      incomplete++;
    } else {
      total += minutes;
      participatory += interactive;
    }
    cards.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(9),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Activity ${index + 1}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 5),
            for (final field in included)
              if (entry.values[field.id] case final value?)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      style: const pw.TextStyle(fontSize: 10),
                      children: [
                        pw.TextSpan(
                          text: '${field.label}: ',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(
                          text: _reportValue(field, value, evidenceNames),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
  final incompleteReport =
      incompleteLayout || incomplete != 0 || records.isEmpty;
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(37),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'CPD Progress Tracker | Internal rehearsal',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          color: PdfColors.indigo900,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                example ? 'SYNTHETIC EXAMPLE' : 'INTERNAL REHEARSAL',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'UK nursing and midwifery CPD activity log',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 19,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Template $recipeVersion | Reporting rules ${rules.version} | Requirements reviewed 21 November 2026',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          incompleteReport ? 'INCOMPLETE ACTIVITY LOG' : 'ACTIVITY SUMMARY',
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: incompleteReport ? PdfColors.red900 : PdfColors.indigo900,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Recorded subtotal from complete entries: ${_minutes(total)} total; ${_minutes(participatory)} participatory.',
        ),
        pw.Text(
          'Scheme reference: 35 hours total including at least 20 participatory hours in the three-year registration period.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (incomplete != 0)
          pw.Text(
            '$incomplete incomplete activities were excluded from the subtotal. Review required fields, evidence references and participatory minutes.',
          ),
        if (incompleteLayout)
          pw.Text(
            'This report configuration is missing scheme inputs. Restore the required fields and their report inclusion to recover compatibility.',
          ),
        pw.SizedBox(height: 5),
        pw.Text(
          'This independent companion supports activity recording. It is not an approved form or a revalidation decision. Official reflective accounts, confirmation and the full renewal period are separate.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 14),
        ...cards,
      ],
    ),
  );
  return document.save();
}

String _minutes(int value) => '${value ~/ 60}h ${value % 60}m';

String _reportValue(
  LayoutField field,
  Object value,
  Map<String, String> evidenceNames,
) {
  if (field.definition.kind == FieldKind.attachments) {
    return (value as List)
        .map((id) => evidenceNames[id] ?? 'Unverified evidence reference')
        .join(', ');
  }
  if (field.definition.kind == FieldKind.duration) {
    return _minutes(value as int);
  }
  final display = field.definition.displayValue(value);
  return display is List ? display.join(', ') : display.toString();
}

Future<Uint8List> nursingSampleReport(
  TemplateVersion recipe,
  ReportSelection selection,
) => buildNursingActivityReport(
  entries: nursingExamples(
    recipe,
  ).map((sample) => PilotReportEntry(recipe.fields, sample.values)),
  selection: selection,
  incompleteLayout: false,
  recipeVersion: recipe.version,
  rules: nursingReportRules,
  requiredBindings: {
    for (final field in recipe.fields.where(nursingReportRules.needs))
      field.definition.id: field.id,
  },
  example: true,
);
