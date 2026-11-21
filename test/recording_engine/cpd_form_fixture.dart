import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/recording_engine/field_library.dart';
import 'package:cpd_tracker/recording_engine/models.dart';

const cpdActiveFieldLimit = 20;

/// The bundled free layout uses the exact canonical migration/adapter bindings.
TemplateVersion cpdFormTemplate() => TemplateVersion(
  id: 'cpd.default',
  version: 1,
  origin: TemplateOrigin.bundled,
  label: 'CPD record',
  description: 'The standard free activity log.',
  translations: const {'fr': 'Activité de formation'},
  fields: cpdStandardFields('cpd.default'),
);

/// Representative research fixtures for internal evaluation. Their inclusion
/// does not select a scheme or imply regulatory acceptance of an export.
final cpdFieldLibrary = FieldLibrary(
  [
    _field(
      'activity.provider',
      'Learning provider',
      'Organisme de formation',
      FieldKind.text,
      'activity',
      'Organisation that delivered the activity.',
      reference: 'D1',
      keywords: ['course provider', 'organisme'],
    ),
    _field(
      'learning.objective',
      'Learning objective',
      'Objectif de formation',
      FieldKind.text,
      'reflection',
      'What you intended to learn.',
      reference: 'D1',
      multiline: true,
      keywords: ['aim', 'learning goal'],
    ),
    _field(
      'outcome.practice_impact',
      'Impact on professional practice',
      'Impact sur la pratique',
      FieldKind.text,
      'reflection',
      'How the activity changed your practice.',
      reference: 'H1',
      multiline: true,
      keywords: ['reflection', 'outcome'],
    ),
    _field(
      'time.participatory_minutes',
      'Participatory CPD time',
      'Durée de formation participative',
      FieldKind.duration,
      'time',
      'Minutes within the activity that involved interaction with others.',
      reference: 'N1',
      tags: ['NMC'],
      keywords: ['participatory hours', 'subset'],
      descriptionTranslations: const {
        'fr': 'Minutes de formation interactive.',
      },
    ),
    _field(
      'time.ca_contact_hours',
      'California RN contact hours',
      'Heures de formation reconnues',
      FieldKind.decimal,
      'time',
      'Contact hours recorded separately from elapsed minutes.',
      reference: 'U1',
      tags: ['CA_RN'],
      keywords: ['continuing education'],
      unit: 'contact hours',
      decimalPlaces: 2,
    ),
    _field(
      'standards.nmc_code',
      'Relevant part of the NMC Code',
      'Thème du code NMC',
      FieldKind.multipleChoices,
      'standards',
      'Themes relevant to this activity.',
      reference: 'X2',
      tags: ['NMC'],
      keywords: ['competency', 'nursing'],
      choices: const {
        'people': 'Prioritise people',
        'effective': 'Practise effectively',
        'safety': 'Preserve safety',
        'trust': 'Promote professionalism and trust',
      },
    ),
    _field(
      'evidence.files',
      'Supporting evidence',
      'Pièces justificatives',
      FieldKind.attachments,
      'evidence',
      'Original evidence for this activity.',
      reference: 'N1',
      keywords: ['certificate', 'proof', 'PDF'],
    ),
    _field(
      'evidence.photo',
      'Evidence photograph',
      'Photo justificative',
      FieldKind.attachments,
      'evidence',
      'An image recording supporting evidence.',
      reference: 'H1',
      keywords: ['photo', 'camera'],
      format: FieldFormat.photograph,
    ),
  ],
  categories: const {
    'activity': {'en': 'Activity details', 'fr': 'Activité'},
    'reflection': {'en': 'Learning and reflection', 'fr': 'Apprentissage'},
    'time': {'en': 'Time and credits', 'fr': 'Durée et crédits'},
    'standards': {'en': 'Standards and competencies', 'fr': 'Compétences'},
    'evidence': {'en': 'Evidence and attachments', 'fr': 'Justificatifs'},
  },
);

LibraryFieldVersion _field(
  String id,
  String label,
  String french,
  FieldKind kind,
  String category,
  String description, {
  required String reference,
  List<String> keywords = const [],
  List<String> tags = const [],
  Map<String, String> descriptionTranslations = const {},
  Map<String, String> choices = const {},
  bool multiline = false,
  String? unit,
  int? decimalPlaces,
  FieldFormat format = FieldFormat.standard,
}) => LibraryFieldVersion(
  source: LibrarySource(id, 1),
  prototype: LayoutField(
    id: id,
    definition: FieldDefinition(
      id: id,
      version: 1,
      label: label,
      kind: kind,
      choices: choices,
      multiline: multiline,
      unit: unit,
      decimalPlaces: decimalPlaces,
      nonNegative: decimalPlaces != null,
      translations: {'fr': french},
    ),
    format: format,
  ),
  category: category,
  description: description,
  descriptionTranslations: descriptionTranslations,
  reference: reference,
  keywords: keywords,
  tags: tags,
);
