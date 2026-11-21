import 'dart:typed_data';

import 'package:cpd_tracker/recording_engine/field_library.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart';
import 'package:pdf/widgets.dart' as pdf;

import 'cpd_form_fixture.dart';
import 'equipment_fixture.dart';

final phase5Library = FieldLibrary(
  [
    ...cpdFieldLibrary.search(''),
    LibraryFieldVersion(
      source: LibrarySource('activity.method', 1),
      prototype: LayoutField(
        id: 'method',
        definition: FieldDefinition(
          id: 'activity.method',
          version: 1,
          label: 'Learning method',
          kind: FieldKind.text,
          translations: const {
            'de': 'Lernmethode',
            'es': 'Método de aprendizaje',
            'fr': 'Méthode d’apprentissage',
            'hi': 'सीखने की विधि',
            'pt': 'Método de aprendizagem',
          },
        ),
      ),
      category: 'activity',
      description: 'How the activity took place, for example a workshop.',
      tags: const ['NMC'],
      keywords: const ['training', 'workshop', 'webinar'],
      reference: 'N1',
    ),
    LibraryFieldVersion(
      source: LibrarySource('activity.start_date', 1),
      prototype: LayoutField(
        id: 'start-date',
        definition: FieldDefinition(
          id: 'activity.start_date',
          version: 1,
          label: 'Activity start date',
          kind: FieldKind.date,
          translations: const {
            'de': 'Beginn der Aktivität',
            'es': 'Inicio de la actividad',
            'fr': 'Début de l’activité',
            'hi': 'गतिविधि शुरू होने की तारीख',
            'pt': 'Início da atividade',
          },
        ),
      ),
      category: 'activity',
      description: 'First day of an activity across multiple dates.',
      tags: const ['NMC'],
      keywords: const ['multi-day', 'start', 'period'],
      reference: 'N1',
    ),
  ],
  categories: const {
    'activity': {
      'en': 'Activity details',
      'de': 'Aktivitätsdetails',
      'es': 'Detalles de la actividad',
      'fr': 'Activité',
      'hi': 'गतिविधि का विवरण',
      'pt': 'Detalhes da atividade',
    },
    'reflection': {
      'en': 'Learning and reflection',
      'de': 'Lernen und Reflexion',
      'es': 'Aprendizaje y reflexión',
      'fr': 'Apprentissage et réflexion',
      'hi': 'सीखना और चिंतन',
      'pt': 'Aprendizagem e reflexão',
    },
    'time': {
      'en': 'Time and credits',
      'de': 'Zeit und Punkte',
      'es': 'Tiempo y créditos',
      'fr': 'Durée et crédits',
      'hi': 'समय और क्रेडिट',
      'pt': 'Tempo e créditos',
    },
    'standards': {
      'en': 'Standards and competencies',
      'de': 'Standards und Kompetenzen',
      'es': 'Normas y competencias',
      'fr': 'Normes et compétences',
      'hi': 'मानक और दक्षताएँ',
      'pt': 'Normas e competências',
    },
    'evidence': {
      'en': 'Evidence and attachments',
      'de': 'Nachweise und Anhänge',
      'es': 'Pruebas y adjuntos',
      'fr': 'Justificatifs',
      'hi': 'साक्ष्य और संलग्नक',
      'pt': 'Comprovativos e anexos',
    },
  },
);

TemplateVersion nursingPreviewTemplate(int version) {
  final standard = cpdFormTemplate().fields;
  final extras = [
    for (final id in [
      'activity.method',
      'activity.start_date',
      'time.participatory_minutes',
      'standards.nmc_code',
      if (version > 1) 'learning.objective',
    ])
      phase5Library.load(id, 1)!.instantiate(id),
  ];
  return TemplateVersion(
    id: 'preview.uk.nursing-activity',
    version: version,
    origin: TemplateOrigin.bundled,
    label: 'UK nursing activity log',
    description: 'A personal learning record for UK nursing and midwifery.',
    translations: const {
      'de': 'Fortbildungsnachweis für Pflegeberufe im Vereinigten Königreich',
      'es': 'Registro de formación de enfermería del Reino Unido',
      'fr': 'Journal de formation infirmière au Royaume-Uni',
      'hi': 'यूके नर्सिंग प्रशिक्षण रिकॉर्ड',
      'pt': 'Registo de formação em enfermagem no Reino Unido',
    },
    fields: [
      ...standard.take(3),
      ...extras.take(2),
      standard[3],
      ...extras.skip(2),
      standard[4],
    ],
    headings: [
      SectionHeading(
        'learning',
        'Learning activity',
        beforeFieldId: standard.first.id,
      ),
    ],
  );
}

final phase5Templates = [
  cpdFormTemplate(),
  nursingPreviewTemplate(1),
  measuredEquipmentTemplate(1),
];

TemplatePreviewExample nursingCompletedExample(
  TemplateVersion template, {
  bool group = true,
}) {
  final label = group
      ? 'Clinical handover workshop'
      : 'Review of infection control guidance';
  final values = <String, Object>{
    'cpd.activityDate': '2026-11-19',
    'cpd.title': label,
    'cpd.details': group
        ? 'Practised a structured handover with colleagues on a simulated shift.'
        : 'Reviewed written guidance and noted changes for the next shift.',
    'cpd.creditedDuration': group ? 90 : 30,
    if (group) 'cpd.evidence': ['preview.sample'],
    'activity.method': group ? 'Peer workshop' : 'Self-directed study',
    'activity.start_date': '2026-11-19',
    'time.participatory_minutes': group ? 60 : 0,
    'standards.nmc_code': group ? ['effective', 'safety'] : ['safety'],
  };
  return TemplatePreviewExample(label, {
    for (final field in template.fields) field.id: ?values[field.definition.id],
  });
}

Future<Uint8List> nursingExamplePdf(
  TemplateVersion template,
  TemplatePreviewExample example,
) {
  final document = pdf.Document();
  document.addPage(
    pdf.MultiPage(
      build: (_) => [
        pdf.Header(level: 0, child: pdf.Text(template.label)),
        pdf.Text(
          'Sample activity report  /  Template version ${template.version}',
        ),
        pdf.SizedBox(height: 12),
        for (final field in template.fields)
          if (example.values[field.id] case final value?)
            pdf.Padding(
              padding: const pdf.EdgeInsets.only(bottom: 8),
              child: pdf.Column(
                crossAxisAlignment: pdf.CrossAxisAlignment.start,
                children: [
                  pdf.Text(
                    field.label,
                    style: pdf.TextStyle(fontWeight: pdf.FontWeight.bold),
                  ),
                  pdf.Text(
                    field.definition.kind == FieldKind.attachments
                        ? 'Sample evidence: Workshop agenda'
                        : '${_display(field.definition.displayValue(value))}${field.definition.kind == FieldKind.duration ? ' minutes' : ''}',
                  ),
                ],
              ),
            ),
      ],
    ),
  );
  return document.save();
}

String _display(Object value) =>
    value is List ? value.join(', ') : value.toString();

final equipmentLibrary = FieldLibrary(
  [
    LibraryFieldVersion(
      source: LibrarySource('maintenance.followup', 1),
      prototype: LayoutField(
        id: 'followup',
        definition: FieldDefinition(
          id: 'maintenance.followup',
          version: 1,
          label: 'Follow-up action',
          kind: FieldKind.text,
          multiline: true,
        ),
      ),
      category: 'service',
      description: 'Record work to carry out after the inspection.',
      keywords: const ['repair', 'next step', 'follow-up'],
    ),
  ],
  categories: const {
    'service': {
      'en': 'Service details',
      'de': 'Wartungsdetails',
      'es': 'Detalles de mantenimiento',
      'fr': 'Détails de maintenance',
      'hi': 'रखरखाव का विवरण',
      'pt': 'Detalhes de manutenção',
    },
  },
);
